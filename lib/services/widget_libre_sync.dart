import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/config/supabase_config.dart';
import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/libre_alert_service.dart';
import 'package:diabetes_app/services/librelinkup_service.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';

/// Shared Libre → widget sync used by the sync button and the 1-min FGS tick.
class WidgetLibreSync {
  WidgetLibreSync._();

  /// Sync Libre glucose into the home widget and refresh IOB.
  ///
  /// When [showSyncing] is true (manual button), shows "Atualizando…" on the
  /// widget. Periodic FGS ticks pass false to avoid flicker every minute.
  ///
  /// Does not start the foreground service — callers that need keep-alive
  /// should call [IobForegroundTask.ensureRunningForWidget] afterwards.
  static Future<bool> refresh({bool showSyncing = false}) async {
    try {
      if (showSyncing) {
        await StatusHomeWidgetService.publish(
          syncing: true,
          clearError: true,
        );
      }

      if (!SupabaseConfig.isConfigured) {
        await StatusHomeWidgetService.publish(
          syncing: false,
          lastError: 'Supabase não configurado',
        );
        return false;
      }

      await _ensureSupabase();

      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        await StatusHomeWidgetService.publish(
          syncing: false,
          libreConnected: false,
          clearGlucose: true,
          lastError: 'Faça login no app',
        );
        return false;
      }

      final libre = LibreLinkUpService(client);
      final status = await libre.status();
      if (!status.connected) {
        await StatusHomeWidgetService.publish(
          syncing: false,
          libreConnected: false,
          clearGlucose: true,
          lastError: showSyncing ? 'Libre não conectado' : null,
          clearError: !showSyncing,
        );
        return false;
      }

      final reading = await libre.syncNow();
      final iobSnap = await IobCache.recompute();
      final iobU = asWholeDose(iobSnap.iobU);

      await StatusHomeWidgetService.publish(
        libreConnected: true,
        reading: reading,
        iobU: iobU,
        syncing: false,
        clearError: true,
      );
      try {
        await LibreAlertService.recordSyncSuccess();
        await LibreAlertService.evaluate(reading, libreConnected: true);
      } catch (e, st) {
        debugPrint('LibreAlertService after sync failed: $e\n$st');
      }
      return true;
    } catch (e, st) {
      debugPrint('WidgetLibreSync.refresh failed: $e\n$st');
      await StatusHomeWidgetService.publish(
        syncing: false,
        lastError: showSyncing ? userFacingError(e) : null,
        clearError: !showSyncing,
      );
      try {
        await LibreAlertService.recordSyncFailure();
      } catch (_) {}
      if (!showSyncing) {
        try {
          final snap = await IobCache.recompute();
          await StatusHomeWidgetService.publishIobTick(asWholeDose(snap.iobU));
        } catch (_) {}
      }
      return false;
    }
  }
}

Future<void> _ensureSupabase() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
}
