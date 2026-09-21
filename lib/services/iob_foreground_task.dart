import 'dart:io' show Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
import 'package:diabetes_app/services/widget_health_sync.dart';
import 'package:diabetes_app/services/widget_libre_sync.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Top-level entry for the IOB / widget foreground-task isolate.
@pragma('vm:entry-point')
void iobForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(IobTaskHandler());
}

/// Android foreground service that every minute:
/// - recomputes IOB
/// - syncs Libre glucose into the home widget (when connected)
/// - syncs Health Connect glucose into glicemias (when enabled)
///
/// Stays running while IOB > 0 **or** Libre is connected **or** Health sync is on.
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
        channelName: 'GlicoDose ao vivo',
        channelDescription:
            'Atualiza IOB e glicose do sensor a cada minuto no widget.',
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
        allowWifiLock: true,
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

  /// Start or update the FGS for IOB > 0. Prefer [ensureRunningForWidget]
  /// when Libre may also be connected.
  static Future<bool> ensureRunning(int n) async {
    if (n <= 0) return false;
    return ensureRunningForWidget(iobU: n);
  }

  /// Keep the 1-min FGS alive for widget glucose sync and/or IOB.
  /// Runs when [iobU] > 0, Libre is connected, or Health sync is enabled.
  static Future<bool> ensureRunningForWidget({required int iobU}) async {
    if (kIsWeb) return false;
    final libreOn = await StatusHomeWidgetService.isLibreConnected();
    final healthOn = await WidgetHealthSync.isEnabled();
    final n = asWholeDose(iobU);
    if (n <= 0 && !libreOn && !healthOn) {
      await stop();
      return false;
    }

    init();
    await ensurePermissions();

    final title = n > 0 ? '~$n U ativas' : 'GlicoDose';
    final body = n > 0
        ? 'Insulina rápida ainda no organismo.'
        : healthOn && !libreOn
            ? 'Sincronizando glicose do Health Connect.'
            : 'Atualizando glicose do sensor a cada minuto.';

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
      debugPrint('IobForegroundTask.ensureRunningForWidget failed: $e\n$st');
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
      await AppBadgePlus.updateBadge(n);
    } catch (_) {}
  }
}

class IobTaskHandler extends TaskHandler {
  Future<void> _tick() async {
    try {
      final snap = await IobCache.recompute();
      final n = asWholeDose(snap.iobU);
      final libreOn = await StatusHomeWidgetService.isLibreConnected();
      final healthOn = await WidgetHealthSync.isEnabled();

      if (libreOn) {
        await WidgetLibreSync.refresh(showSyncing: false);
      } else {
        await StatusHomeWidgetService.publishIobTick(n);
      }
      if (healthOn) {
        await WidgetHealthSync.refresh(lookback: const Duration(hours: 3));
      }

      // Re-read prefs after sync (may have flipped libre_connected).
      final stillLibre = await StatusHomeWidgetService.isLibreConnected();
      final stillHealth = await WidgetHealthSync.isEnabled();
      final iobAfter = libreOn
          ? asWholeDose((await IobCache.recompute()).iobU)
          : n;

      if (iobAfter <= 0 && !stillLibre && !stillHealth) {
        FlutterForegroundTask.sendDataToMain(
          {IobForegroundTask.dataKeyIobU: 0},
        );
        await FlutterForegroundTask.stopService();
        try {
          await AppBadgePlus.updateBadge(0);
        } catch (_) {}
        return;
      }

      final title = iobAfter > 0 ? '~$iobAfter U ativas' : 'GlicoDose';
      final body = iobAfter > 0
          ? 'Insulina rápida ainda no organismo.'
          : stillHealth && !stillLibre
              ? 'Sincronizando glicose do Health Connect.'
              : 'Atualizando glicose do sensor a cada minuto.';
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
      try {
        await AppBadgePlus.updateBadge(iobAfter);
      } catch (_) {}
      FlutterForegroundTask.sendDataToMain(
        {IobForegroundTask.dataKeyIobU: iobAfter},
      );
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
