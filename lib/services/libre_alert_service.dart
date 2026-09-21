import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/libre_alert_logic.dart';

/// Local Libre hypo/hyper/stale alerts (FGS + foreground ticks).
class LibreAlertService {
  LibreAlertService._();

  static const channelId = 'libre_glucose_alerts';
  static const channelName = 'Alertas de glicose Libre';

  static const prefEnabled = 'libre_alerts_enabled';
  static const prefHypo = 'libre_alert_hypo_mgdl';
  static const prefHyper = 'libre_alert_hyper_mgdl';
  static const prefStaleMinutes = 'libre_alert_stale_minutes';
  static const prefZone = 'libre_alert_zone';
  static const prefLastAlertAt = 'libre_alert_last_at';
  static const prefLastRecordedAt = 'libre_alert_last_recorded_at';
  static const prefLastSuccessSyncAt = 'libre_alert_last_success_sync_at';
  static const prefStaleAlertAt = 'libre_alert_stale_at';
  static const prefFailCount = 'libre_alert_fail_count';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: 'Alertas de hipoglicemia, hiperglicemia e sensor parado',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    _initialized = true;
  }

  static Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    await ensureInitialized();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidOk =
        await androidPlugin?.requestNotificationsPermission() ?? true;
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosOk = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;
    return androidOk && iosOk;
  }

  static Future<void> applyFromProfile(Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefEnabled, profile.libreAlertsEnabled);
    await prefs.setInt(prefHypo, profile.libreAlertHypoMgdl);
    await prefs.setInt(prefHyper, profile.libreAlertHyperMgdl);
    await prefs.setInt(prefStaleMinutes, profile.libreAlertStaleMinutes);
  }

  static Future<LibreAlertLogic> _logic() async {
    final prefs = await SharedPreferences.getInstance();
    return LibreAlertLogic(
      hypoMgdl: prefs.getInt(prefHypo) ?? 70,
      hyperMgdl: prefs.getInt(prefHyper) ?? 180,
      staleMinutes: prefs.getInt(prefStaleMinutes) ?? 20,
    );
  }

  static Future<void> recordSyncSuccess({DateTime? at}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefLastSuccessSyncAt,
      (at ?? DateTime.now()).toUtc().toIso8601String(),
    );
    await prefs.setInt(prefFailCount, 0);
  }

  static Future<void> recordSyncFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt(prefFailCount) ?? 0) + 1;
    await prefs.setInt(prefFailCount, n);
    final enabled = prefs.getBool(prefEnabled) ?? false;
    final libreOn = true; // caller only invokes when Libre path is active
    if (!enabled) return;
    final logic = await _logic();
    final lastSuccess = _parseIso(prefs.getString(prefLastSuccessSyncAt));
    final decision = logic.evaluateStale(
      now: DateTime.now(),
      lastSuccessSyncAt: lastSuccess,
      libreConnected: libreOn,
      alertsEnabled: enabled,
      lastStaleAlertAt: _parseIso(prefs.getString(prefStaleAlertAt)),
      consecutiveFailures: n,
    );
    if (decision.shouldNotify) {
      await _show(decision);
      await prefs.setString(
        prefStaleAlertAt,
        DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  static Future<void> evaluate(
    LibreGlucoseReading reading, {
    bool libreConnected = true,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(prefEnabled) ?? false;
    if (!enabled || !libreConnected) return;

    await ensureInitialized();
    final logic = await _logic();
    final now = DateTime.now();
    final previous =
        LibreAlertLogic.zoneFromName(prefs.getString(prefZone));
    final decision = logic.evaluateReading(
      reading: reading,
      previousZone: previous,
      now: now,
      lastAlertAt: _parseIso(prefs.getString(prefLastAlertAt)),
      lastAlertedRecordedAt: _parseIso(prefs.getString(prefLastRecordedAt)),
    );

    await prefs.setString(prefZone, LibreAlertLogic.zoneName(decision.zone));

    if (decision.shouldNotify) {
      await _show(decision);
      await prefs.setString(prefLastAlertAt, now.toUtc().toIso8601String());
      if (reading.recordedAt != null) {
        await prefs.setString(
          prefLastRecordedAt,
          reading.recordedAt!.toUtc().toIso8601String(),
        );
      }
      if (decision.notificationId == LibreAlertLogic.hypoNotificationId) {
        await _plugin.cancel(id: LibreAlertLogic.hyperNotificationId);
      } else if (decision.notificationId ==
          LibreAlertLogic.hyperNotificationId) {
        await _plugin.cancel(id: LibreAlertLogic.hypoNotificationId);
      }
    } else if (decision.zone == LibreAlertZone.ok) {
      await _plugin.cancel(id: LibreAlertLogic.hypoNotificationId);
      await _plugin.cancel(id: LibreAlertLogic.hyperNotificationId);
    }

    final stale = logic.evaluateStale(
      now: now,
      lastSuccessSyncAt: _parseIso(prefs.getString(prefLastSuccessSyncAt)),
      libreConnected: libreConnected,
      alertsEnabled: enabled,
      lastStaleAlertAt: _parseIso(prefs.getString(prefStaleAlertAt)),
      sampleRecordedAt: reading.recordedAt,
      consecutiveFailures: prefs.getInt(prefFailCount) ?? 0,
    );
    if (stale.shouldNotify) {
      await _show(stale);
      await prefs.setString(
        prefStaleAlertAt,
        now.toUtc().toIso8601String(),
      );
    } else {
      await _plugin.cancel(id: LibreAlertLogic.staleNotificationId);
    }
  }

  static Future<void> _show(LibreAlertDecision decision) async {
    final id = decision.notificationId;
    if (id == null || decision.title == null) return;
    await ensureInitialized();
    await _plugin.show(
      id: id,
      title: decision.title,
      body: decision.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription:
              'Alertas de hipoglicemia, hiperglicemia e sensor parado',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
  }

  /// Show alert from FCM data payload (dedupe IDs with local).
  static Future<void> showFromPush({
    required String type,
    required String title,
    required String body,
  }) async {
    final id = switch (type) {
      'libre_hypo' => LibreAlertLogic.hypoNotificationId,
      'libre_hyper' => LibreAlertLogic.hyperNotificationId,
      'libre_stale' => LibreAlertLogic.staleNotificationId,
      _ => null,
    };
    if (id == null) return;
    await _show(
      LibreAlertDecision(
        zone: LibreAlertZone.ok,
        shouldNotify: true,
        title: title,
        body: body,
        notificationId: id,
      ),
    );
  }

  static DateTime? _parseIso(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}
