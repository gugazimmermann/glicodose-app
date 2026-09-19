import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/config/supabase_config.dart';
import 'package:diabetes_app/services/brazil_time.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  BrazilTime.ensureInitialized();

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
