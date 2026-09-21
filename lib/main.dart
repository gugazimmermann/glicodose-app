import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/config/supabase_config.dart';
import 'package:diabetes_app/services/brazil_time.dart';
import 'package:diabetes_app/services/iob_background.dart';
import 'package:diabetes_app/services/iob_foreground_task.dart';
import 'package:diabetes_app/services/status_home_widget_callback.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  BrazilTime.ensureInitialized();
  _installErrorHandlers();

  if (!kIsWeb) {
    IobForegroundTask.init();
    await Workmanager().initialize(iobBackgroundCallbackDispatcher);
    await registerStatusHomeWidgetCallback();
  }

  if (!SupabaseConfig.isConfigured) {
    FlutterNativeSplash.remove();
    runApp(const _ConfigMissingApp());
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  final services = AppServices(Supabase.instance.client);
  try {
    await services.support.configure();
    final userId = services.auth.currentUser?.id;
    if (userId != null) {
      await services.support.logIn(userId);
    }
  } catch (e, st) {
    // IAP optional until store keys are configured.
    assert(() {
      // ignore: avoid_print
      print('RevenueCat configure failed: $e\n$st');
      return true;
    }());
  }

  runApp(DiabetesApp(services: services));
}

void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    // ignore: avoid_print
    print('Uncaught error: $error\n$stack');
    return true;
  };

  ErrorWidget.builder = (details) {
    return ColoredBox(
      color: const Color(0xFFB71C1C),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Algo deu errado\n\n${details.exceptionAsString()}',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  };
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Configuração necessária',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'Defina SUPABASE_URL e SUPABASE_ANON_KEY via --dart-define '
                  'ou edite lib/config/supabase_config.dart.',
                ),
                SizedBox(height: 12),
                Text(
                  'Veja o README.md para o setup completo do Supabase e da Edge Function.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
