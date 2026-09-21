import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/screens/health_import_screen.dart';
import 'package:diabetes_app/screens/history_charts_tab.dart';
import 'package:diabetes_app/screens/history_screen.dart';
import 'package:diabetes_app/screens/home_screen.dart';
import 'package:diabetes_app/screens/main_shell.dart';
import 'package:diabetes_app/screens/profile_screen.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/history_stats.dart';
import 'package:diabetes_app/theme/app_theme.dart';

import 'fakes/fake_app_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> setLargeSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );
  }

  Entry sampleEntry({
    String id = 'e1',
    int glucose = 140,
    double? applied,
    DateTime? recordedAt,
  }) {
    return Entry(
      id: id,
      userId: FakeAppServices.userId,
      recordedAt: recordedAt ?? DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      glucoseMgdl: glucose,
      recommendedInsulin: 5,
      appliedInsulin: applied,
      foodText: 'pão',
      gptRawResponse: const {'carboidratos_g': 40},
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('HomeScreen smoke renders glucose form with fakes', (tester) async {
    await setLargeSurface(tester);
    final fake = FakeAppServices.create(
      entries: [sampleEntry(applied: null)],
    );

    await tester.pumpWidget(
      wrap(HomeScreen(services: fake.services, embedded: true)),
    );
    await settle(tester);

    expect(find.text('mg/dL'), findsOneWidget);
    expect(find.textContaining('Estimar carbs'), findsOneWidget);
    expect(find.textContaining('Dose pendente'), findsOneWidget);
  });

  testWidgets('HistoryScreen smoke shows empty and populated states',
      (tester) async {
    await setLargeSurface(tester);
    final empty = FakeAppServices.create();
    await tester.pumpWidget(
      wrap(HistoryScreen(services: empty.services, embedded: true)),
    );
    await settle(tester);
    expect(find.text('Lista'), findsOneWidget);
    expect(find.text('Nenhum registro ainda'), findsOneWidget);

    final populated = FakeAppServices.create(
      entries: [sampleEntry(applied: 4)],
      basalDoses: [
        BasalDose(
          id: 'b1',
          userId: FakeAppServices.userId,
          // Must fall inside the bolus page window (not older than oldest entry).
          recordedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
          units: 18,
          insulinName: 'Tresiba',
        ),
      ],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      wrap(
        HistoryScreen(
          key: const ValueKey('history-populated'),
          services: populated.services,
          embedded: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('140'), findsWidgets);
    expect(find.text('Basal'), findsWidgets);
  });

  testWidgets('HistoryChartsTab smoke renders stats with samples', (tester) async {
    await setLargeSurface(tester);
    final now = DateTime.utc(2026, 9, 21, 12);
    final fake = FakeAppServices.create(
      entries: [sampleEntry(applied: 4)],
      glucoseSamples: [
        GlucoseSample(glucoseMgdl: 100, recordedAt: now),
        GlucoseSample(
          glucoseMgdl: 120,
          recordedAt: now.add(const Duration(hours: 1)),
        ),
        GlucoseSample(
          glucoseMgdl: 90,
          recordedAt: now.add(const Duration(hours: 2)),
        ),
      ],
    );

    await tester.pumpWidget(
      wrap(HistoryChartsTab(services: fake.services)),
    );
    await settle(tester);

    expect(find.text('7 dias'), findsOneWidget);
    expect(find.textContaining('TIR'), findsWidgets);
  });

  testWidgets('ProfileScreen smoke loads complete profile fields', (tester) async {
    await setLargeSurface(tester);
    final fake = FakeAppServices.create();
    await tester.pumpWidget(
      wrap(ProfileScreen(services: fake.services, embedded: true)),
    );
    await settle(tester);

    expect(find.text('Tester'), findsOneWidget);
    expect(find.text('Humalog'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Sair da conta'), findsOneWidget);

    await tester.ensureVisible(find.text('Sair da conta'));
    await tester.tap(find.text('Sair da conta'));
    await settle(tester);
    expect((fake.services.auth as FakeAuthService).signedOut, isTrue);
  });

  testWidgets('HealthImportScreen smoke shows Libre + Health sections',
      (tester) async {
    await setLargeSurface(tester);
    final fake = FakeAppServices.create();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HealthImportScreen(services: fake.services),
      ),
    );
    await settle(tester);

    expect(find.text('Linkar Sensor'), findsOneWidget);
    expect(find.text('LibreLinkUp'), findsOneWidget);
    expect(find.textContaining('seguidor'), findsOneWidget);
  });

  testWidgets('MainShell smoke switches tabs with fakes', (tester) async {
    await setLargeSurface(tester);
    final fake = FakeAppServices.create(
      entries: [sampleEntry(applied: 3)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MainShell(services: fake.services),
      ),
    );
    await settle(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('mg/dL'), findsOneWidget);

    await tester.tap(find.text('Histórico'));
    await settle(tester);
    expect(find.text('Lista'), findsOneWidget);
    expect(find.text('140'), findsWidgets);

    await tester.tap(find.text('Perfil'));
    await settle(tester);
    expect(find.text('Humalog'), findsOneWidget);

    await tester.tap(find.text('Apoiar'));
    await settle(tester);
  });
}
