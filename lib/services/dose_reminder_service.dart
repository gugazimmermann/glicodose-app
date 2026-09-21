import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/basal_reminder_logic.dart';

/// Schedules post-bolus glucose checks and daily basal reminders.
class DoseReminderService {
  DoseReminderService();

  static const notificationId = 72001;
  static const channelId = 'glicodose_dose_reminders';
  static const channelName = 'Lembretes de dose';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: 'Lembretes de dose e checagem de glicose',
        importance: Importance.defaultImportance,
      ),
    );
    _initialized = true;
  }

  /// Reminds the user to check glucose [delay] after confirming a dose.
  Future<void> schedulePostBolusCheck({
    Duration delay = const Duration(hours: 2),
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();
    AppTime.ensureInitialized();
    final when = AppTime.now().add(delay);
    await _plugin.zonedSchedule(
      id: notificationId,
      title: 'Checar glicose',
      body: 'Já se passaram 2 h desde a última dose. Vale medir a glicemia.',
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'Lembretes de dose e checagem de glicose',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelPostBolusCheck() async {
    if (kIsWeb) return;
    await ensureInitialized();
    await _plugin.cancel(id: notificationId);
  }

  /// Daily basal reminders at [timesMinutes] (profile timezone).
  Future<void> scheduleBasalReminders({
    required List<int> timesMinutes,
    String? timezone,
    String? insulinName,
    double? doseU,
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();
    await cancelBasalReminders();

    final times = BasalReminderLogic.normalizeTimes(timesMinutes);
    if (times.isEmpty) return;

    AppTime.ensureInitialized();
    final namePart = (insulinName != null && insulinName.trim().isNotEmpty)
        ? insulinName.trim()
        : 'basal';
    final dosePart = doseU != null && doseU > 0
        ? ' (${doseU.toStringAsFixed(doseU == doseU.roundToDouble() ? 0 : 1)} U)'
        : '';

    final occurrences = BasalReminderLogic.nextOccurrences(
      timesMinutes: times,
      timezone: timezone,
    );

    for (var i = 0; i < occurrences.length; i++) {
      final when = occurrences[i];
      final id = BasalReminderLogic.notificationIds[i];
      await _plugin.zonedSchedule(
        id: id,
        title: 'Insulina basal',
        body: 'Hora da $namePart$dosePart.',
        scheduledDate: when,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'Lembretes de dose e checagem de glicose',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> cancelBasalReminders() async {
    if (kIsWeb) return;
    await ensureInitialized();
    for (final id in BasalReminderLogic.notificationIds) {
      await _plugin.cancel(id: id);
    }
  }

  /// Sync local basal notifications from profile flags.
  Future<void> syncBasalFromProfile({
    required bool enabled,
    required List<int> timesMinutes,
    String? timezone,
    String? insulinName,
    double? doseU,
  }) async {
    if (!enabled || timesMinutes.isEmpty) {
      await cancelBasalReminders();
      return;
    }
    await scheduleBasalReminders(
      timesMinutes: timesMinutes,
      timezone: timezone,
      insulinName: insulinName,
      doseU: doseU,
    );
  }
}
