import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/iob_foreground_task.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Top-level entry point for Workmanager isolates (must not be a class method).
@pragma('vm:entry-point')
void iobBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await IobBackground.recomputeAndApply();
    } catch (e, st) {
      debugPrint('iobBackgroundCallbackDispatcher failed: $e\n$st');
      return false;
    }
    return true;
  });
}

/// Coarse fallback when the FGS was killed or after reboot (Android).
class IobBackground {
  IobBackground._();

  static const uniqueName = 'iob_live_periodic';
  static const taskName = 'iob_live_tick';

  /// Shared path used by Workmanager: cache → restart FGS / clear badge.
  static Future<int> recomputeAndApply({DateTime? now}) async {
    final snap = await IobCache.recompute(now: now);
    final n = asWholeDose(snap.iobU);
    await StatusHomeWidgetService.publishIobTick(n);
    if (n > 0) {
      IobForegroundTask.init();
      await IobForegroundTask.ensureRunning(n);
    } else {
      await IobForegroundTask.stop();
      await cancel();
    }
    return n > 0 ? n : 0;
  }

  static Future<void> ensureScheduled() async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerPeriodicTask(
        uniqueName,
        taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
    } catch (e, st) {
      debugPrint('IobBackground.ensureScheduled failed: $e\n$st');
    }
  }

  static Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelByUniqueName(uniqueName);
    } catch (e, st) {
      debugPrint('IobBackground.cancel failed: $e\n$st');
    }
  }
}
