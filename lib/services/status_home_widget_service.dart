import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Publishes glucose + IOB to the Android home-screen App Widget.
class StatusHomeWidgetService {
  StatusHomeWidgetService._();

  static const androidQualifiedName =
      'com.diabetes.diabetes_app.GlicoDoseWidgetProvider';

  static const keyLibreConnected = 'libre_connected';
  static const keyHasGlucose = 'has_glucose';
  static const keyGlucoseMgdl = 'glucose_mgdl';
  static const keyTrendLabel = 'trend_label';
  static const keyGlucoseAge = 'glucose_age';
  static const keyGlucoseRecordedAt = 'glucose_recorded_at';
  static const keyIobU = 'iob_u';
  static const keySyncing = 'syncing';
  static const keyLastError = 'last_error';
  static const keyUpdatedAt = 'updated_at';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> publish({
    bool? libreConnected,
    LibreGlucoseReading? reading,
    bool clearGlucose = false,
    int? iobU,
    bool? syncing,
    String? lastError,
    bool clearError = false,
  }) async {
    if (!_supported) return;
    try {
      if (libreConnected != null) {
        await HomeWidget.saveWidgetData<bool>(
          keyLibreConnected,
          libreConnected,
        );
      }

      if (clearGlucose) {
        await HomeWidget.saveWidgetData<bool>(keyHasGlucose, false);
        await HomeWidget.saveWidgetData<int?>(keyGlucoseMgdl, null);
        await HomeWidget.saveWidgetData<String?>(keyTrendLabel, null);
        await HomeWidget.saveWidgetData<String?>(keyGlucoseAge, null);
        await HomeWidget.saveWidgetData<String?>(keyGlucoseRecordedAt, null);
      } else if (reading != null) {
        await HomeWidget.saveWidgetData<bool>(keyHasGlucose, true);
        await HomeWidget.saveWidgetData<int>(
          keyGlucoseMgdl,
          reading.glucoseMgdl,
        );
        await HomeWidget.saveWidgetData<String>(
          keyTrendLabel,
          reading.trendLabel,
        );
        await HomeWidget.saveWidgetData<String>(
          keyGlucoseAge,
          reading.ageLabel,
        );
        await HomeWidget.saveWidgetData<String?>(
          keyGlucoseRecordedAt,
          reading.recordedAt?.toIso8601String(),
        );
        if (libreConnected == null) {
          await HomeWidget.saveWidgetData<bool>(keyLibreConnected, true);
        }
      } else {
        await _refreshGlucoseAgeLabel();
      }

      if (iobU != null) {
        await HomeWidget.saveWidgetData<int>(keyIobU, asWholeDose(iobU));
      }

      if (syncing != null) {
        await HomeWidget.saveWidgetData<bool>(keySyncing, syncing);
      }

      if (clearError) {
        await HomeWidget.saveWidgetData<String?>(keyLastError, null);
      } else if (lastError != null) {
        await HomeWidget.saveWidgetData<String>(keyLastError, lastError);
      }

      await HomeWidget.saveWidgetData<String>(
        keyUpdatedAt,
        DateTime.now().toIso8601String(),
      );
      await _updateWidget();
    } catch (e, st) {
      debugPrint('StatusHomeWidgetService.publish failed: $e\n$st');
    }
  }

  /// Recompute age label + IOB for periodic ticks (FGS / Workmanager).
  static Future<void> publishIobTick(int iobU) async {
    if (!_supported) return;
    try {
      await _refreshGlucoseAgeLabel();
      await HomeWidget.saveWidgetData<int>(keyIobU, asWholeDose(iobU));
      await HomeWidget.saveWidgetData<String>(
        keyUpdatedAt,
        DateTime.now().toIso8601String(),
      );
      await _updateWidget();
    } catch (e, st) {
      debugPrint('StatusHomeWidgetService.publishIobTick failed: $e\n$st');
    }
  }

  static Future<void> clear() async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<bool>(keyLibreConnected, false);
      await HomeWidget.saveWidgetData<bool>(keyHasGlucose, false);
      await HomeWidget.saveWidgetData<int?>(keyGlucoseMgdl, null);
      await HomeWidget.saveWidgetData<String?>(keyTrendLabel, null);
      await HomeWidget.saveWidgetData<String?>(keyGlucoseAge, null);
      await HomeWidget.saveWidgetData<String?>(keyGlucoseRecordedAt, null);
      await HomeWidget.saveWidgetData<int>(keyIobU, 0);
      await HomeWidget.saveWidgetData<bool>(keySyncing, false);
      await HomeWidget.saveWidgetData<String?>(keyLastError, null);
      await HomeWidget.saveWidgetData<String>(
        keyUpdatedAt,
        DateTime.now().toIso8601String(),
      );
      await _updateWidget();
    } catch (e, st) {
      debugPrint('StatusHomeWidgetService.clear failed: $e\n$st');
    }
  }

  static Future<void> _refreshGlucoseAgeLabel() async {
    final iso = await HomeWidget.getWidgetData<String>(keyGlucoseRecordedAt);
    if (iso == null || iso.isEmpty) return;
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return;
    final reading = LibreGlucoseReading(
      glucoseMgdl:
          await HomeWidget.getWidgetData<int>(keyGlucoseMgdl) ?? 0,
      recordedAt: at,
    );
    await HomeWidget.saveWidgetData<String>(keyGlucoseAge, reading.ageLabel);
  }

  static Future<void> _updateWidget() async {
    await HomeWidget.updateWidget(
      name: 'GlicoDoseWidgetProvider',
      androidName: 'GlicoDoseWidgetProvider',
      qualifiedAndroidName: androidQualifiedName,
    );
  }
}
