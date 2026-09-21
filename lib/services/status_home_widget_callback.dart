import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/iob_foreground_task.dart';
import 'package:diabetes_app/services/widget_libre_sync.dart';
import 'package:diabetes_app/utils/dose_format.dart';

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

/// Invoked from the Android / iOS home widget Sync button (may run in a fresh isolate).
@pragma('vm:entry-point')
Future<void> statusHomeWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'syncLibre') return;
  WidgetsFlutterBinding.ensureInitialized();
  final ok = await WidgetLibreSync.refresh(showSyncing: true);
  if (ok) {
    final snap = await IobCache.recompute();
    await IobForegroundTask.ensureRunningForWidget(
      iobU: asWholeDose(snap.iobU),
    );
  }
}
