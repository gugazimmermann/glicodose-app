import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/screens/dose_result_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (call) async => null,
        );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'public-anon-key',
    );
    services = AppServices(Supabase.instance.client);
  });

  testWidgets('DoseResultScreen renders dose title, value and Nova dose', (
    tester,
  ) async {
    // Tall surface so ListView builds the footer buttons immediately.
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final entry = Entry(
      id: 'entry-1',
      userId: 'user-1',
      recordedAt: DateTime.utc(2026, 1, 15, 12),
      glucoseMgdl: 140,
      recommendedInsulin: 5,
    );

    const recommendation = InsulinRecommendation(
      carboidratosG: 45,
      correcaoU: 1,
      bolusComidaU: 4,
      insulinaRecomendadaU: 5,
      iobU: 0,
      source: 'ai',
      confianca: 'media',
      observacao: 'Estimativa de teste',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DoseResultScreen(
          services: services,
          entry: entry,
          recommendation: recommendation,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Resultado da dose'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('Insulina recomendada'), findsOneWidget);
    expect(find.textContaining('Confiança nos carbs'), findsOneWidget);
    expect(find.text('Nova dose'), findsOneWidget);
    expect(find.text('Recalcular com estes carbs'), findsOneWidget);
    expect(find.textContaining('Peso estimado'), findsNothing);
  });

  testWidgets(
    'DoseResultScreen shows estimated weight when peso_g is present',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final entry = Entry(
        id: 'entry-2',
        userId: 'user-1',
        recordedAt: DateTime.utc(2026, 1, 15, 12),
        glucoseMgdl: 140,
        foodText: 'arroz',
        recommendedInsulin: 5,
      );
      final recommendation = InsulinRecommendation.fromJson({
        'carboidratos_g': 45,
        'peso_g': 180,
        'gordura_g': 12,
        'proteina_g': 0,
        'correcao_u': 1,
        'bolus_comida_u': 4,
        'insulina_recomendada_u': 5,
        'confianca': 'media',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DoseResultScreen(
            services: services,
            entry: entry,
            recommendation: recommendation,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Peso estimado: 180 g'), findsOneWidget);
      expect(find.text('Gordura'), findsOneWidget);
      expect(find.text('12 g'), findsWidgets);
      expect(find.text('Proteína'), findsOneWidget);
      expect(find.text('0 g'), findsOneWidget);
      expect(find.text('Salvar como receita'), findsOneWidget);
    },
  );
}
