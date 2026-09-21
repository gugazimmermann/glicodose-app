import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/screens/dose_result_screen.dart';
import 'package:diabetes_app/screens/health_import_screen.dart';
import 'package:diabetes_app/screens/history_charts_tab.dart';
import 'package:diabetes_app/screens/history_screen.dart';
import 'package:diabetes_app/screens/home_screen.dart';
import 'package:diabetes_app/screens/profile_screen.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/history_stats.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/services/theme_preference_service.dart';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      ThemePreferenceService.channel,
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'requestNotificationsPermission') return true;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async => true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
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
    await tester.binding.setSurfaceSize(const Size(900, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Entry sampleEntry({
    String id = 'e1',
    int glucose = 140,
    double? applied,
    String? food,
  }) {
    return Entry(
      id: id,
      userId: FakeAppServices.userId,
      recordedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      glucoseMgdl: glucose,
      recommendedInsulin: 5,
      appliedInsulin: applied,
      foodText: food ?? 'pão',
      gptRawResponse: const {
        'carboidratos_g': 40,
        'correcao_u': 1,
        'bolus_comida_u': 4,
        'insulina_recomendada_u': 5,
      },
    );
  }

  group('HomeScreen interactions', () {
    testWidgets('AI mode requires food text before calculating', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        wrap(HomeScreen(services: fake.services, embedded: true)),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextFormField).first, '150');
      await tester.ensureVisible(find.text('Estimar carbs e calcular'));
      await tester.tap(find.text('Estimar carbs e calcular'));
      await settle(tester);

      expect(find.textContaining('Informe o alimento'), findsOneWidget);
      expect(fake.entries.items, isEmpty);
    });

    testWidgets('manual carbs calculates and opens DoseResultScreen',
        (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextFormField).first, '210');
      await tester.ensureVisible(find.text('Carbs manuais'));
      await tester.tap(find.text('Carbs manuais'));
      await settle(tester);

      expect(find.text('Calcular com fórmula'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Carboidratos (g)'),
        '40',
      );
      await tester.ensureVisible(find.text('Calcular com fórmula'));
      await tester.tap(find.text('Calcular com fórmula'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Resultado da dose'), findsOneWidget);
      expect(fake.entries.items, hasLength(1));
      expect(fake.entries.items.first.glucoseMgdl, 210);
      expect(fake.entries.items.first.appliedInsulin, isNull);
      expect(fake.entries.items.first.recommendedInsulin, greaterThan(0));

      // Confirm applied dose on result screen.
      await tester.ensureVisible(find.text('Confirmar dose aplicada'));
      await tester.tap(find.text('Confirmar dose aplicada'));
      await settle(tester);

      expect(fake.entries.items.first.appliedInsulin, isNotNull);
      expect(find.textContaining('Dose confirmada'), findsWidgets);
      expect(find.text('Atualizar dose aplicada'), findsOneWidget);
    });

    testWidgets('registers basal via bottom sheet', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Registrar basal'));
      await tester.tap(find.text('Registrar basal').first);
      await tester.pumpAndSettle();

      expect(find.text('Salvar basal'), findsOneWidget);
      await tester.tap(find.text('Salvar basal'));
      await tester.pumpAndSettle();

      final doses = await fake.services.basal.listDoses();
      expect(doses, hasLength(1));
      expect(doses.first.units, 18);
      expect(doses.first.insulinName, 'Tresiba');
      expect(find.textContaining('Basal registrada'), findsWidgets);
    });

    testWidgets('Libre connected fills glucose and syncs', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        libreStatus: LibreConnectionStatus(
          connected: true,
          email: 'libre@test.com',
          region: 'eu',
          latest: LibreGlucoseReading(
            glucoseMgdl: 155,
            recordedAt: DateTime.now(),
            trend: 3,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('155'), findsWidgets);
      expect(find.textContaining('Libre'), findsWidgets);
      await tester.tap(find.byTooltip('Atualizar do Libre'));
      await settle(tester);
      expect(find.text('155'), findsWidgets);
    });

    testWidgets('pending unconfirmed dose banner opens result', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        entries: [
          sampleEntry(id: 'pending', glucose: 168, applied: null),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Dose pendente de confirmação'), findsOneWidget);
      expect(find.textContaining('168 mg/dL'), findsOneWidget);
      await tester.tap(find.textContaining('Dose pendente de confirmação'));
      await settle(tester);
      expect(find.byType(DoseResultScreen), findsOneWidget);
    });

    testWidgets('speech fills food description', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.byTooltip('Falar'));
      await tester.tap(find.byTooltip('Falar'));
      await settle(tester);
      await tester.tap(find.byTooltip('Parar'));
      await settle(tester);
      expect(find.text('arroz feijão'), findsOneWidget);
    });

    testWidgets('low glucose shows hypo warning', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextFormField).first, '65');
      await settle(tester);
      expect(find.textContaining('Glicose baixa (< 70)'), findsOneWidget);
    });

    testWidgets('falling Libre trend warns before bolus', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        libreStatus: LibreConnectionStatus(
          connected: true,
          email: 't@t.com',
          region: 'eu',
          latest: LibreGlucoseReading(
            glucoseMgdl: 100,
            recordedAt: DateTime.now(),
            trend: 2,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Tendência Libre'), findsOneWidget);
    });

    testWidgets('active IOB banner shows remaining units', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      (fake.services.iobLive as FakeIobLiveController).snapshot.value =
          const IobSnapshot(iobU: 2.4, contributions: []);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(services: fake.services),
        ),
      );
      await settle(tester);
      expect(find.textContaining('U ativas'), findsOneWidget);
    });
  });

  group('DoseResultScreen interactions', () {
    testWidgets('confirm applied updates entry and shows snackbar',
        (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        entries: [sampleEntry(applied: null)],
      );
      final entry = fake.entries.items.first;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DoseResultScreen(
            services: fake.services,
            entry: entry,
            recommendation: InsulinRecommendation.fromEntry(entry),
          ),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Confirmar dose aplicada'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Insulina aplicada (U)'),
        '4',
      );
      await tester.tap(find.text('Confirmar dose aplicada'));
      await settle(tester);

      expect(fake.entries.items.first.appliedInsulin, 4);
      expect(find.textContaining('Dose confirmada'), findsWidgets);
      expect(find.text('Atualizar dose aplicada'), findsOneWidget);
    });
  });

  group('ProfileScreen interactions', () {
    testWidgets('save profile upserts via fake', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        wrap(ProfileScreen(services: fake.services, embedded: true)),
      );
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome (opcional)'),
        'Ana Silva',
      );
      await tester.ensureVisible(find.text('Salvar perfil'));
      await tester.tap(find.text('Salvar perfil'));
      await settle(tester);

      expect(fake.profile.upsertCalls, greaterThan(0));
      expect(fake.profile.profile?.fullName, 'Ana Silva');
      expect(find.text('Perfil salvo'), findsOneWidget);
    });

    testWidgets('Linkar Sensor opens HealthImportScreen', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfileScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Linkar Sensor'));
      await tester.tap(find.text('Linkar Sensor'));
      await settle(tester);

      expect(find.byType(HealthImportScreen), findsOneWidget);
      expect(find.text('LibreLinkUp'), findsOneWidget);
    });
  });

  group('HistoryScreen interactions', () {
    testWidgets('opens dose detail from list', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        entries: [sampleEntry(applied: 5)],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: HistoryScreen(services: fake.services, embedded: true),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('140').first);
      await settle(tester);
      expect(find.text('Detalhe da dose'), findsOneWidget);
      expect(find.textContaining('Insulina recomendada'), findsOneWidget);
    });

    testWidgets('deletes entry from overflow menu', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        entries: [sampleEntry(applied: 5)],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: HistoryScreen(services: fake.services, embedded: true),
          ),
        ),
      );
      await settle(tester);

      final menu = find.byIcon(Icons.more_vert).hitTestable();
      expect(menu, findsWidgets);
      await tester.tap(menu.last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(find.text('Remover este registro?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
      await tester.pumpAndSettle();

      expect(fake.entries.items, isEmpty);
      expect(find.text('Nenhum registro ainda'), findsOneWidget);
    });

    testWidgets('edits entry from overflow menu', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        entries: [sampleEntry(applied: 5)],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HistoryScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.tap(find.byIcon(Icons.more_vert).hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();

      expect(find.text('Editar registro'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Glicose (mg/dL)'),
        '155',
      );
      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      expect(fake.entries.items.first.glucoseMgdl, 155);
      expect(find.textContaining('Registro atualizado'), findsWidgets);
    });

    testWidgets('removes basal from timeline', (tester) async {
      await setLargeSurface(tester);
      final now = DateTime.now().toUtc();
      final fake = FakeAppServices.create(
        entries: [
          Entry(
            id: 'e1',
            userId: FakeAppServices.userId,
            recordedAt: now.subtract(const Duration(hours: 2)),
            glucoseMgdl: 140,
            recommendedInsulin: 4,
            appliedInsulin: 4,
          ),
        ],
        basalDoses: [
          BasalDose(
            id: 'b1',
            userId: FakeAppServices.userId,
            recordedAt: now.subtract(const Duration(hours: 1)),
            units: 18,
            insulinName: 'Tresiba',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HistoryScreen(services: fake.services),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Basal'), findsWidgets);
      await tester.tap(find.byIcon(Icons.more_vert).hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(find.text('Remover basal?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
      await tester.pumpAndSettle();
      expect(await fake.basal.listDoses(), isEmpty);
    });

    testWidgets('shows page footer for list', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        entries: [
          sampleEntry(id: 'a', applied: 2),
          sampleEntry(id: 'b', glucose: 150, applied: 3),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HistoryScreen(services: fake.services, embedded: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Página 1 de 1'), findsOneWidget);
      expect(find.textContaining('2 bolus'), findsOneWidget);
    });

    testWidgets('export menu opens CSV and report items', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(entries: [sampleEntry(applied: 3)]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HistoryScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.tap(find.byTooltip('Exportar'));
      await tester.pumpAndSettle();
      expect(find.text('Exportar CSV'), findsOneWidget);
      expect(find.text('Relatório para consulta'), findsOneWidget);
      await tester.tap(find.text('Exportar CSV'));
      await tester.pumpAndSettle();
    });
  });

  group('HistoryChartsTab interactions', () {
    testWidgets('switches period chips', (tester) async {
      await setLargeSurface(tester);
      final now = DateTime.now().toUtc();
      final fake = FakeAppServices.create(
        entries: [sampleEntry(applied: 3)],
        glucoseSamples: [
          GlucoseSample(glucoseMgdl: 100, recordedAt: now),
          GlucoseSample(
            glucoseMgdl: 130,
            recordedAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
      );
      await tester.pumpWidget(
        wrap(HistoryChartsTab(services: fake.services)),
      );
      await settle(tester);

      expect(find.text('7 dias'), findsOneWidget);
      await tester.tap(find.text('30 dias'));
      await settle(tester);
      expect(find.text('30 dias'), findsOneWidget);
      await tester.tap(find.text('Tudo'));
      await settle(tester);
      expect(find.textContaining('TIR'), findsWidgets);
    });
  });

  group('ProfileScreen theme', () {
    testWidgets('switching theme persists on profile fake', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        wrap(ProfileScreen(services: fake.services, embedded: true)),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Escuro'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.byIcon(Icons.dark_mode_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.profile.upsertCalls, greaterThan(0));
      expect(fake.profile.profile?.theme, 'dark');
      expect(
        (await SharedPreferences.getInstance()).getString('theme_mode'),
        'dark',
      );
    });
  });

  group('HealthImportScreen interactions', () {
    testWidgets('connect Libre with fakes updates status UI', (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HealthImportScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail LibreLinkUp'),
        'follower@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'secret',
      );
      await tester.ensureVisible(find.text('Conectar'));
      await tester.tap(find.text('Conectar'));
      await settle(tester);

      expect(find.textContaining('Conta seguidor conectada'), findsOneWidget);
      expect(find.text('follower@example.com'), findsOneWidget);
    });

    testWidgets('shows connected state when fake libre already linked',
        (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        libreStatus: LibreConnectionStatus(
          connected: true,
          email: 'ja@conectado.com',
          region: 'eu',
          latest: LibreGlucoseReading(
            glucoseMgdl: 118,
            recordedAt: DateTime.now(),
            trend: 3,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HealthImportScreen(services: fake.services),
        ),
      );
      await settle(tester);

      expect(find.textContaining('Conta seguidor conectada'), findsOneWidget);
      expect(find.text('ja@conectado.com'), findsOneWidget);
      expect(find.textContaining('118'), findsWidgets);
    });

    testWidgets('disconnect Libre confirms and returns to connect form',
        (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        libreStatus: LibreConnectionStatus(
          connected: true,
          email: 'sair@example.com',
          region: 'eu',
          latest: LibreGlucoseReading(
            glucoseMgdl: 110,
            recordedAt: DateTime.now(),
            trend: 3,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HealthImportScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Desconectar'));
      await tester.tap(find.text('Desconectar'));
      await tester.pumpAndSettle();
      expect(find.text('Desconectar LibreLinkUp?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Desconectar'));
      await settle(tester);

      expect(find.textContaining('LibreLinkUp desconectado'), findsOneWidget);
      expect(find.text('Conectar'), findsOneWidget);
    });

    testWidgets('Atualizar agora shows sync snackbar when linked',
        (tester) async {
      await setLargeSurface(tester);
      final fake = FakeAppServices.create(
        libreStatus: LibreConnectionStatus(
          connected: true,
          email: 'sync@example.com',
          region: 'eu',
          latest: LibreGlucoseReading(
            glucoseMgdl: 125,
            recordedAt: DateTime.now(),
            trend: 3,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HealthImportScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Atualizar agora'));
      await tester.tap(find.text('Atualizar agora'));
      await settle(tester);

      expect(
        find.textContaining(RegExp(r'Glicemia atualizada|Falha ao sincronizar')),
        findsOneWidget,
      );
    });

    testWidgets('Health Connect ready enables sync and imports samples',
        (tester) async {
      await setLargeSurface(tester);
      final now = DateTime.now();
      final health = FakeHealthPlatformService(
        supported: true,
        avail: HealthPlatformAvailability.ready,
        label: 'Health Connect',
        authorized: true,
        latest: PlatformGlucoseReading(
          glucoseMgdl: 142,
          recordedAt: now,
          sourceName: 'Libre',
        ),
        history: [
          PlatformGlucoseReading(
            glucoseMgdl: 140,
            recordedAt: now.subtract(const Duration(hours: 1)),
            sourceName: 'Libre',
          ),
          PlatformGlucoseReading(
            glucoseMgdl: 145,
            recordedAt: now.subtract(const Duration(hours: 2)),
            sourceName: 'Libre',
          ),
        ],
      );
      final fake = FakeAppServices.create(health: health);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HealthImportScreen(services: fake.services),
        ),
      );
      await settle(tester);

      expect(find.text('Health Connect'), findsWidgets);
      expect(find.textContaining('142'), findsWidgets);

      await tester.ensureVisible(find.text('Sincronizar em segundo plano'));
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      expect(fake.profile.upsertCalls, greaterThan(0));
      expect(fake.profile.profile?.healthSyncEnabled, isTrue);
    });

    testWidgets('Autorizar e buscar glicose shows reading snackbar',
        (tester) async {
      await setLargeSurface(tester);
      final health = FakeHealthPlatformService(
        supported: true,
        avail: HealthPlatformAvailability.ready,
        label: 'Health Connect',
        latest: PlatformGlucoseReading(
          glucoseMgdl: 133,
          recordedAt: DateTime.now(),
          sourceName: 'CGM',
        ),
      );
      final fake = FakeAppServices.create(health: health);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HealthImportScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Autorizar e buscar glicose'));
      await tester.tap(find.text('Autorizar e buscar glicose'));
      await settle(tester);

      expect(find.textContaining('Última glicose: 133'), findsOneWidget);
    });

    testWidgets('Importar histórico backfills glicemias via fake',
        (tester) async {
      await setLargeSurface(tester);
      final now = DateTime.now();
      final health = FakeHealthPlatformService(
        supported: true,
        avail: HealthPlatformAvailability.ready,
        label: 'Health Connect',
        authorized: true,
        latest: PlatformGlucoseReading(
          glucoseMgdl: 150,
          recordedAt: now,
          sourceName: 'Libre',
        ),
        history: [
          PlatformGlucoseReading(
            glucoseMgdl: 148,
            recordedAt: now.subtract(const Duration(hours: 3)),
            sourceName: 'Libre',
          ),
          PlatformGlucoseReading(
            glucoseMgdl: 151,
            recordedAt: now.subtract(const Duration(hours: 6)),
            sourceName: 'Libre',
          ),
        ],
      );
      final fake = FakeAppServices.create(health: health);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HealthImportScreen(services: fake.services),
        ),
      );
      await settle(tester);

      await tester.ensureVisible(find.text('Importar histórico (30 dias)'));
      await tester.tap(find.text('Importar histórico (30 dias)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 amostras importadas'), findsWidgets);
    });
  });
}
