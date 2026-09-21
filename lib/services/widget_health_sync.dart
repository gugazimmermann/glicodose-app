import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/config/supabase_config.dart';
import 'package:diabetes_app/services/glicemia_service.dart';
import 'package:diabetes_app/services/health_platform_service.dart';

/// Shared Health → glicemias sync for Linkar Sensor and the 1-min FGS tick.
class WidgetHealthSync {
  WidgetHealthSync._();

  static const keyHealthSyncEnabled = 'health_sync_enabled';

  static Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    try {
      return await HomeWidget.getWidgetData<bool>(keyHealthSyncEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<bool>(keyHealthSyncEnabled, enabled);
    } catch (e, st) {
      debugPrint('WidgetHealthSync.setEnabled failed: $e\n$st');
    }
  }

  /// Pull recent Health glucose into `glicemias`. Returns upsert count.
  static Future<int> refresh({
    Duration lookback = const Duration(hours: 6),
    HealthPlatformService? health,
    GlicemiaService? glicemias,
  }) async {
    try {
      if (!await isEnabled()) return 0;
      if (!SupabaseConfig.isConfigured) return 0;

      await _ensureSupabase();
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return 0;

      final platform = health ?? HealthPlatformService();
      if (!platform.isSupportedPlatform) return 0;

      final avail = await platform.availability();
      if (avail != HealthPlatformAvailability.ready) return 0;

      final readings = await platform.glucoseHistory(lookback: lookback);
      if (readings.isEmpty) return 0;

      final service = glicemias ?? GlicemiaService(client);
      return await service.upsertHealthReadings(readings);
    } catch (e, st) {
      debugPrint('WidgetHealthSync.refresh failed: $e\n$st');
      return 0;
    }
  }
}

Future<void> _ensureSupabase() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
}
