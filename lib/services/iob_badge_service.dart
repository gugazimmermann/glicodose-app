import 'dart:io' show Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/iob_foreground_task.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Keeps the launcher icon badge in sync with active rapid insulin (IOB).
///
/// While IOB > 0 on Android, the status notification is owned by
/// [IobForegroundTask] (real FGS). This service still updates the launcher
/// badge and cancels the legacy local-notification fallback.
class IobBadgeService {
  IobBadgeService({
    required EntryService entries,
    required ProfileService profile,
  })  : _entries = entries,
        _profile = profile;

  static const notificationId = 71001;
  static const legacyChannelId = 'iob_badge';
  static const channelId = 'iob_status';

  final EntryService _entries;
  final ProfileService _profile;
  final IobService _iob = const IobService();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _notificationAsked = false;
  bool _notificationsInitialized = false;

  /// Request permission (if needed) and initialize the notification plugin.
  Future<void> ensureReady() async {
    await _initNotifications();
    await ensureNotificationPermission();
  }

  Future<void> ensureNotificationPermission() async {
    if (_notificationAsked) return;
    _notificationAsked = true;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isRestricted) {
        await Permission.notification.request();
      }
      if (!kIsWeb && Platform.isAndroid) {
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        await _notifications
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: false, badge: true, sound: false);
        await _notifications
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: false, badge: true, sound: false);
      }
    } catch (_) {
      // Non-blocking: badge may still work on some launchers.
    }
  }

  Future<void> refresh() async {
    try {
      await _initNotifications();

      final profile = await _profile.fetchCurrent();
      final duration = profile?.insulinDurationHours ?? 4.0;
      if (duration <= 0) {
        await applyCount(0);
        return;
      }

      final since =
          DateTime.now().subtract(Duration(hours: duration.ceil() + 1));
      final entries = await _entries.listEntriesSince(since);
      final snap = _iob.computeIob(
        recentEntries: entries,
        durationHours: duration,
        now: DateTime.now(),
      );
      final n = asWholeDose(snap.iobU);
      await applyCount(n > 0 ? n : 0);
    } catch (_) {
      // Ignore badge failures (unsupported launcher, offline, etc.).
    }
  }

  Future<void> clear() async {
    try {
      await applyCount(0);
    } catch (_) {}
  }

  /// Updates launcher badge. By default also syncs the legacy local
  /// notification unless [skipNotification] is true (FGS owns the status bar)
  /// or the FGS is already running.
  Future<void> applyCount(int n, {bool skipNotification = false}) async {
    await _initNotifications();
    await _applyLauncherBadge(n);

    final fgsRunning = await IobForegroundTask.isRunning;
    if (skipNotification || fgsRunning) {
      // Cancel any leftover legacy ongoing notification to avoid duplicates.
      await _cancelLegacyNotification();
      return;
    }

    await _syncNotification(n, _notifications);
  }

  /// Same as [applyCount] but usable from a Workmanager isolate (no DI).
  /// Prefer restarting the FGS when IOB > 0; falls back to local notification.
  static Future<void> applyCountStandalone(int n) async {
    try {
      await AppBadgePlus.updateBadge(n);
    } catch (_) {}

    if (n > 0) {
      await IobForegroundTask.ensureRunning(n);
      // Cancel legacy channel notification if any.
      final plugin = FlutterLocalNotificationsPlugin();
      await _initNotificationsPlugin(plugin);
      try {
        await plugin.cancel(id: notificationId);
      } catch (_) {}
      return;
    }

    await IobForegroundTask.stop();
    final plugin = FlutterLocalNotificationsPlugin();
    await _initNotificationsPlugin(plugin);
    await _syncNotification(0, plugin);
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialized || kIsWeb) return;
    await _initNotificationsPlugin(_notifications);
    _notificationsInitialized = true;
  }

  static Future<void> _initNotificationsPlugin(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    if (kIsWeb) return;
    try {
      const android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: true,
        requestSoundPermission: false,
      );
      await plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
    } catch (_) {
      // Keep going; AppBadgePlus path may still work.
    }
  }

  Future<void> _applyLauncherBadge(int n) async {
    try {
      await AppBadgePlus.updateBadge(n);
    } catch (_) {}
  }

  Future<void> _cancelLegacyNotification() async {
    if (kIsWeb) return;
    try {
      await _notifications.cancel(id: notificationId);
    } catch (_) {}
  }

  static Future<void> _syncNotification(
    int n,
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    if (kIsWeb) return;

    if (n <= 0) {
      await notifications.cancel(id: notificationId);
      return;
    }

    // Drop any leftover from the previous low-importance channel id.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.deleteNotificationChannel(channelId: legacyChannelId);
      } catch (_) {}
    }

    // Legacy fallback only when FGS could not start (e.g. iOS / denied).
    await notifications.show(
      id: notificationId,
      title: '~$n U ativas',
      body: 'Insulina rápida ainda no organismo.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Insulina ativa (IOB)',
          channelDescription:
              'Mostra quantas unidades de insulina rápida ainda estão ativas.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          ongoing: true,
          channelShowBadge: true,
          number: n,
          autoCancel: false,
          category: AndroidNotificationCategory.status,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: true,
          presentSound: false,
          badgeNumber: n,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: true,
          presentSound: false,
          badgeNumber: n,
        ),
      ),
    );
  }
}
