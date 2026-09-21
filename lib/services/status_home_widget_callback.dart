import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/config/supabase_config.dart';
import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/librelinkup_service.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';

/// Registers the interactive-widget callback (call once from [main]).
Future<void> registerStatusHomeWidgetCallback() async {
  if (kIsWeb) return;
  try {
    await HomeWidget.registerInteractivityCallback(
      statusHomeWidgetBackgroundCallback,
    );
  } catch (e, st) {
    debugPrint('registerStatusHomeWidgetCallback failed: $e\n$st');
  }
}

/// Invoked from the Android App Widget Sync button (may run in a fresh isolate).
@pragma('vm:entry-point')
Future<void> statusHomeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'syncLibre') return;

  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StatusHomeWidgetService.publish(
      syncing: true,
      clearError: true,
    );

    if (!SupabaseConfig.isConfigured) {
      await StatusHomeWidgetService.publish(
        syncing: false,
        lastError: 'Supabase não configurado',
      );
      return;
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
      return;
    }

    final libre = LibreLinkUpService(client);
    final status = await libre.status();
    if (!status.connected) {
      await StatusHomeWidgetService.publish(
        syncing: false,
        libreConnected: false,
        clearGlucose: true,
        lastError: 'Libre não conectado',
      );
      return;
    }

    final reading = await libre.syncNow();
    final iobSnap = await IobCache.recompute();

    await StatusHomeWidgetService.publish(
      libreConnected: true,
      reading: reading,
      iobU: asWholeDose(iobSnap.iobU),
      syncing: false,
      clearError: true,
    );
  } catch (e, st) {
    debugPrint('statusHomeWidgetBackgroundCallback failed: $e\n$st');
    await StatusHomeWidgetService.publish(
      syncing: false,
      lastError: userFacingError(e),
    );
  }
}

Future<void> _ensureSupabase() async {
  // initialize() is a no-op when already initialized in this isolate.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
}
