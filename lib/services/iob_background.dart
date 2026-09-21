import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'package:diabetes_app/services/iob_badge_service.dart';
import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Top-level entry point for Workmanager isolates (must not be a class method).
@pragma('vm:entry-point')
void iobBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await IobBackground.recomputeAndApply();
    } catch (_) {
      // Never crash the worker isolate.
    }
    return true;
  });
}

/// Unique / task names for the IOB background recompute job (Android).
class IobBackground {
  IobBackground._();

  static const uniqueName = 'iob_live_periodic';
  static const taskName = 'iob_live_tick';

  /// Shared path used by Workmanager (and tests): cache → badge/notification.
  static Future<int> recomputeAndApply({DateTime? now}) async {
    final snap = await IobCache.recompute(now: now);
    final n = asWholeDose(snap.iobU);
    await IobBadgeService.applyCountStandalone(n > 0 ? n : 0);
    if (n <= 0) {
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
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
    } catch (_) {
      // Unsupported platform or OEM restriction.
    }
  }

  static Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelByUniqueName(uniqueName);
    } catch (_) {}
  }
}
