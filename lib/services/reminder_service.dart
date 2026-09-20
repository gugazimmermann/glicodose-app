import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:diabetes_app/services/brazil_time.dart';

/// Daily meal / glucose reminders (local notifications).
class ReminderService {
  ReminderService();

  static const _prefsGlucose = 'reminder_glucose_enabled';
  static const _prefsMeal = 'reminder_meal_enabled';
  static const _prefsGlucoseHour = 'reminder_glucose_hour';
  static const _prefsGlucoseMinute = 'reminder_glucose_minute';
  static const _prefsMealHour = 'reminder_meal_hour';
  static const _prefsMealMinute = 'reminder_meal_minute';

  static const _glucoseId = 72001;
  static const _mealId = 72002;
  static const _channelId = 'glicodose_reminders';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    BrazilTime.ensureInitialized();
    tz.setLocalLocation(BrazilTime.location);

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      'Lembretes GlicoDose',
      description: 'Lembretes de glicemia e refeição',
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _ready = true;
  }

  Future<ReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return ReminderSettings(
      glucoseEnabled: prefs.getBool(_prefsGlucose) ?? false,
      mealEnabled: prefs.getBool(_prefsMeal) ?? false,
      glucoseHour: prefs.getInt(_prefsGlucoseHour) ?? 8,
      glucoseMinute: prefs.getInt(_prefsGlucoseMinute) ?? 0,
      mealHour: prefs.getInt(_prefsMealHour) ?? 12,
      mealMinute: prefs.getInt(_prefsMealMinute) ?? 0,
    );
  }

  Future<void> saveAndReschedule(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsGlucose, settings.glucoseEnabled);
    await prefs.setBool(_prefsMeal, settings.mealEnabled);
    await prefs.setInt(_prefsGlucoseHour, settings.glucoseHour);
    await prefs.setInt(_prefsGlucoseMinute, settings.glucoseMinute);
    await prefs.setInt(_prefsMealHour, settings.mealHour);
    await prefs.setInt(_prefsMealMinute, settings.mealMinute);
    await ensureReady();
    await _plugin.cancel(id: _glucoseId);
    await _plugin.cancel(id: _mealId);

    if (settings.glucoseEnabled) {
      await _scheduleDaily(
        id: _glucoseId,
        hour: settings.glucoseHour,
        minute: settings.glucoseMinute,
        title: 'Hora de medir a glicemia',
        body: 'Registre sua glicose no GlicoDose.',
      );
    }
    if (settings.mealEnabled) {
      await _scheduleDaily(
        id: _mealId,
        hour: settings.mealHour,
        minute: settings.mealMinute,
        title: 'Lembrete de refeição',
        body: 'Registre a refeição e a dose no app.',
      );
    }
  }

  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final when = _nextInstanceOf(hour, minute);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Lembretes GlicoDose',
          channelDescription: 'Lembretes de glicemia e refeição',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

class ReminderSettings {
  const ReminderSettings({
    required this.glucoseEnabled,
    required this.mealEnabled,
    required this.glucoseHour,
    required this.glucoseMinute,
    required this.mealHour,
    required this.mealMinute,
  });

  final bool glucoseEnabled;
  final bool mealEnabled;
  final int glucoseHour;
  final int glucoseMinute;
  final int mealHour;
  final int mealMinute;

  ReminderSettings copyWith({
    bool? glucoseEnabled,
    bool? mealEnabled,
    int? glucoseHour,
    int? glucoseMinute,
    int? mealHour,
    int? mealMinute,
  }) {
    return ReminderSettings(
      glucoseEnabled: glucoseEnabled ?? this.glucoseEnabled,
      mealEnabled: mealEnabled ?? this.mealEnabled,
      glucoseHour: glucoseHour ?? this.glucoseHour,
      glucoseMinute: glucoseMinute ?? this.glucoseMinute,
      mealHour: mealHour ?? this.mealHour,
      mealMinute: mealMinute ?? this.mealMinute,
    );
  }
}
