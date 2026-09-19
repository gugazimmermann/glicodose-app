import 'dart:io' show Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Keeps the launcher icon badge in sync with active rapid insulin (IOB).
///
/// On many Android launchers (Pixel/stock, HyperOS), `app_badge_plus` alone is
/// a no-op — a local notification with [AndroidNotificationDetails.number] is
/// required for the icon badge/dot. Pixel still shows only a dot on the icon;
/// an ongoing status notification carries the readable `~N U` count.
class IobBadgeService {
  IobBadgeService({
    required EntryService entries,
    required ProfileService profile,
  })  : _entries = entries,
        _profile = profile;

  static const _notificationId = 71001;
  static const _legacyChannelId = 'iob_badge';
  static const _channelId = 'iob_status';

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
        await _applyBadge(0);
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
      await _applyBadge(n > 0 ? n : 0);
    } catch (_) {
      // Ignore badge failures (unsupported launcher, offline, etc.).
    }
  }

  Future<void> clear() async {
    try {
      await _applyBadge(0);
    } catch (_) {}
  }

  Future<void> _applyBadge(int n) async {
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(n);
      }
    } catch (_) {}

    // Notification fallback: required on Pixel/stock and several OEMs where
    // launcher badge APIs are missing or no-ops.
    await _syncNotification(n);
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialized || kIsWeb) return;
    try {
      const android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: true,
        requestSoundPermission: false,
      );
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
      _notificationsInitialized = true;
    } catch (_) {
      // Keep going; AppBadgePlus path may still work.
    }
  }

  Future<void> _syncNotification(int n) async {
    if (kIsWeb || !_notificationsInitialized) return;

    if (n <= 0) {
      await _notifications.cancel(id: _notificationId);
      return;
    }

    // Drop any leftover from the previous low-importance channel id.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.deleteNotificationChannel(channelId: _legacyChannelId);
      } catch (_) {}
    }

    await _notifications.show(
      id: _notificationId,
      title: '~$n U ativas',
      body: 'Insulina rápida ainda no organismo.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
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
