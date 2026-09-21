import 'dart:io' show Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Top-level entry for the IOB foreground-task isolate.
@pragma('vm:entry-point')
void iobForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(IobTaskHandler());
}

/// Android foreground service that recomputes IOB every minute and updates
/// the status notification + launcher badge while IOB > 0.
class IobForegroundTask {
  IobForegroundTask._();

  static const serviceId = 71002;
  /// Bumped to v2 so Android recreates the channel with [showBadge] enabled
  /// (channel badge flag is immutable after first creation).
  static const channelId = 'iob_fg_v2';
  static const dataKeyIobU = 'iob_u';

  static bool _initialized = false;
  static bool _batteryPrompted = false;

  static void init() {
    if (kIsWeb || _initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        // New channel id: showBadge is fixed at channel creation time on Android 8+.
        channelId: channelId,
        channelName: 'Insulina ativa (IOB)',
        channelDescription:
            'Mostra quantas unidades de insulina rápida ainda estão ativas.',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
        onlyAlertOnce: true,
        showBadge: true,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  static Future<void> ensurePermissions() async {
    if (kIsWeb) return;
    try {
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!kIsWeb && Platform.isAndroid && !_batteryPrompted) {
        _batteryPrompted = true;
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
    } catch (e, st) {
      debugPrint('IobForegroundTask.ensurePermissions failed: $e\n$st');
    }
  }

  /// Start or update the FGS with the current whole-unit IOB count.
  /// Returns `true` when the service is running afterwards.
  static Future<bool> ensureRunning(int n) async {
    if (kIsWeb || n <= 0) return false;
    init();
    await ensurePermissions();

    final title = '~$n U ativas';
    const body = 'Insulina rápida ainda no organismo.';

    try {
      if (await FlutterForegroundTask.isRunningService) {
        final result = await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: body,
        );
        if (result is ServiceRequestFailure) {
          debugPrint('IobForegroundTask.updateService failed: ${result.error}');
        }
      } else {
        final result = await FlutterForegroundTask.startService(
          serviceId: serviceId,
          serviceTypes: const [ForegroundServiceTypes.specialUse],
          notificationTitle: title,
          notificationText: body,
          callback: iobForegroundStartCallback,
        );
        if (result is ServiceRequestFailure) {
          debugPrint('IobForegroundTask.startService failed: ${result.error}');
          await _applyLauncherBadge(n);
          return false;
        }
      }
      await _applyLauncherBadge(n);
      return await FlutterForegroundTask.isRunningService;
    } catch (e, st) {
      debugPrint('IobForegroundTask.ensureRunning failed: $e\n$st');
      await _applyLauncherBadge(n);
      return false;
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e, st) {
      debugPrint('IobForegroundTask.stop failed: $e\n$st');
    }
    await _applyLauncherBadge(0);
  }

  static Future<bool> get isRunning async {
    if (kIsWeb) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _applyLauncherBadge(int n) async {
    try {
      // Always attempt — isSupported() is false on Pixel (dot-only) and on
      // OEMs before permissions; updateBadge is still needed on Samsung/etc.
      await AppBadgePlus.updateBadge(n);
    } catch (_) {}
  }
}

class IobTaskHandler extends TaskHandler {
  Future<void> _tick() async {
    try {
      final snap = await IobCache.recompute();
      final n = asWholeDose(snap.iobU);
      await StatusHomeWidgetService.publishIobTick(n);
      if (n <= 0) {
        FlutterForegroundTask.sendDataToMain({IobForegroundTask.dataKeyIobU: 0});
        await FlutterForegroundTask.stopService();
        try {
          await AppBadgePlus.updateBadge(0);
        } catch (_) {}
        return;
      }

      await FlutterForegroundTask.updateService(
        notificationTitle: '~$n U ativas',
        notificationText: 'Insulina rápida ainda no organismo.',
      );
      try {
        await AppBadgePlus.updateBadge(n);
      } catch (_) {}
      FlutterForegroundTask.sendDataToMain({IobForegroundTask.dataKeyIobU: n});
    } catch (e, st) {
      debugPrint('IobTaskHandler._tick failed: $e\n$st');
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Fire-and-forget; TaskHandler API is sync void.
    // ignore: discarded_futures
    _tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}
