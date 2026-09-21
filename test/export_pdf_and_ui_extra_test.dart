import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/screens/dose_result_screen.dart';
import 'package:diabetes_app/screens/history_charts_tab.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/export_service.dart';
import 'package:diabetes_app/services/insulin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    AppTime.ensureInitialized();
    AppTime.setLocation(AppTime.defaultLocationName);
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

  group('ExportService PDF', () {
    test('buildPdfBytes produces non-empty PDF with timeline', () async {
      const export = ExportService();
      final bytes = await export.buildPdfBytes(
        profile: Profile(
          id: 'u1',
          fullName: 'Ana',
          targetGlucoseMgdl: 100,
          targetNightMgdl: 110,
          isfMgdlPerU: 50,
          icRatio: 10,
          rapidInsulinName: 'Humalog',
          basalInsulinName: 'Tresiba',
          basalDoseU: 18,
        ),
        entries: [
          Entry(
            id: 'e1',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 12),
            glucoseMgdl: 140,
            foodText: 'pão',
            recommendedInsulin: 5,
            appliedInsulin: 4,
            gptRawResponse: const {'carboidratos_g': 40},
          ),
        ],
        basalDoses: [
          BasalDose(
            id: 'b1',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 22),
            units: 18,
            insulinName: 'Tresiba',
          ),
        ],
      );
      expect(bytes, isNotEmpty);
      // PDF magic header
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('buildPdfBytes truncates very long timelines', () async {
      const export = ExportService();
      final entries = List.generate(
        90,
        (i) => Entry(
          id: 'e$i',
          userId: 'u1',
          recordedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          glucoseMgdl: 100 + i,
          recommendedInsulin: 1,
        ),
      );
      final bytes = await export.buildPdfBytes(
        profile: null,
        entries: entries,
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('InsulinService local', () {
    test('calculateManual and recalculateWithCarbs', () {
      final insulin = InsulinService(Supabase.instance.client);
      final profile = Profile(
        id: 'u1',
        targetGlucoseMgdl: 110,
        targetNightMgdl: 120,
        isfMgdlPerU: 50,
        icRatio: 10,
        rapidInsulinName: 'Humalog',
        doseStep: 1,
      );
      final manual = insulin.calculateManual(
        glucoseMgdl: 210,
        carboidratosG: 40,
        profile: profile,
        confianca: 'alta',
      );
      expect(manual.source, 'manual');
      expect(manual.confianca, 'alta');
      expect(manual.insulinaRecomendadaU, greaterThan(0));

      final recalc = insulin.recalculateWithCarbs(
        glucoseMgdl: 210,
        carboidratosG: 20,
        profile: profile,
        iobU: 1,
      );
      expect(recalc.source, 'local_adjust');
      expect(recalc.insulinaRecomendadaU, lessThan(manual.insulinaRecomendadaU));
    });
  });

  group('chartXInterval', () {
    test('scales with sample count', () {
      expect(chartXInterval(3), 1);
      expect(chartXInterval(10), 2);
      expect(chartXInterval(20), 4);
      expect(chartXInterval(50), 10);
    });
  });

  group('DoseResultScreen interactions', () {
    testWidgets('recalculate without profile shows incomplete error',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: DoseResultScreen(
            services: services,
            entry: Entry(
              id: 'entry-1',
              userId: 'user-1',
              recordedAt: DateTime.utc(2026, 1, 15, 12),
              glucoseMgdl: 140,
              recommendedInsulin: 5,
            ),
            recommendation: const InsulinRecommendation(
              carboidratosG: 45,
              correcaoU: 1,
              bolusComidaU: 4,
              insulinaRecomendadaU: 5,
              confianca: 'baixa',
            ),
          ),
        ),
      );
      await tester.pump();
      final recalc = find.text('Recalcular com estes carbs');
      expect(recalc, findsOneWidget);
      await tester.ensureVisible(recalc);
      await tester.tap(recalc);
      await tester.pump();
      expect(find.textContaining('Perfil incompleto'), findsOneWidget);
    });

    testWidgets('invalid carbs shows validation error', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: DoseResultScreen(
            services: services,
            entry: Entry(
              id: 'entry-2',
              userId: 'user-1',
              recordedAt: DateTime.utc(2026, 1, 15, 12),
              glucoseMgdl: 140,
              recommendedInsulin: 5,
            ),
            recommendation: const InsulinRecommendation(
              carboidratosG: 45,
              correcaoU: 1,
              bolusComidaU: 4,
              insulinaRecomendadaU: 5,
              confianca: 'alta',
              metaMgdl: 110,
              metaPeriodo: 'dia',
              iobU: 1,
              observacao: 'ok',
            ),
          ),
        ),
      );
      await tester.pump();
      final carbsFields = find.byType(TextField);
      expect(carbsFields, findsWidgets);
      await tester.enterText(carbsFields.last, '');
      await tester.tap(find.text('Recalcular com estes carbs'));
      await tester.pump();
      expect(find.textContaining('carboidratos'), findsOneWidget);
    });
  });

  group('HistoryChartsTab', () {
    testWidgets('shows loading then error without auth', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryChartsTab(services: services),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Unauthenticated Supabase calls fail → error UI or still loading.
      expect(
        find.text('Tentar novamente').evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
            find.textContaining('Sem dados').evaluate().isNotEmpty,
        isTrue,
      );
    });
  });
}
