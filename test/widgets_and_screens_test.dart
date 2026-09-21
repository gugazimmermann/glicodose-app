import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/screens/disclaimer_screen.dart';
import 'package:diabetes_app/screens/login_screen.dart';
import 'package:diabetes_app/screens/splash_screen.dart';
import 'package:diabetes_app/screens/support_screen.dart';
import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/support_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/widgets/app_logo.dart';
import 'package:diabetes_app/widgets/disclaimer_banner.dart';
import 'package:diabetes_app/widgets/section_card.dart';
import 'package:diabetes_app/widgets/support_cta_banner.dart';
import 'package:diabetes_app/widgets/support_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_native_splash'),
      (call) async => null,
    );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'public-anon-key',
    );
  });

  Widget wrap(Widget child, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme ?? AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(body: child),
    );
  }

  group('widgets', () {
    testWidgets('SectionCard with title and icon', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SectionCard(
            title: 'Seção',
            icon: Icons.star,
            child: Text('conteúdo'),
          ),
        ),
      );
      expect(find.text('Seção'), findsOneWidget);
      expect(find.text('conteúdo'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('DisclaimerBanner shows clinical disclaimer', (tester) async {
      await tester.pumpWidget(wrap(const DisclaimerBanner()));
      expect(find.textContaining('Não substitui'), findsOneWidget);
    });

    testWidgets('AppLogo with title and AppBarLogoTitle', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Column(
            children: [
              AppLogo(showTitle: true, subtitle: 'apoio'),
              AppBarLogoTitle(title: 'Histórico'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('GlicoDose'), findsOneWidget);
      expect(find.text('apoio'), findsOneWidget);
      expect(find.text('Histórico'), findsOneWidget);
    });

    testWidgets('SupportCtaBanner hides when not configured', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          SupportCtaBanner(
            onTap: () => tapped = true,
            visible: true,
          ),
        ),
      );
      expect(find.byType(SizedBox), findsWidgets);
      expect(tapped, isFalse);

      await tester.pumpWidget(
        wrap(
          SupportCtaBanner(
            onTap: () => tapped = true,
            visible: false,
          ),
        ),
      );
      expect(find.textContaining('apoie'), findsNothing);
    });

    testWidgets('SupportSection shrinks on unsupported platform', (tester) async {
      await tester.pumpWidget(
        wrap(
          SupportSection(
            support: SupportService(),
            profileStatus: 'active',
            profileProductId: 'support_10',
          ),
        ),
      );
      await tester.pump();
      // Linux/desktop host → SizedBox.shrink
      expect(find.text('Apoiar o GlicoDose'), findsNothing);
    });
  });

  group('screens smoke', () {
    late AppServices services;

    setUp(() {
      services = AppServices(Supabase.instance.client);
    });

    testWidgets('SplashScreen finishes after min display', (tester) async {
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SplashScreen(onFinished: () => finished = true),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1700));
      expect(finished, isTrue);
      expect(find.text('GlicoDose'), findsOneWidget);
    });

    testWidgets('LoginScreen validates empty fields', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LoginScreen(services: services),
        ),
      );
      await tester.pump();
      expect(find.text('Entrar'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pump();
      expect(find.text('Informe o e-mail'), findsOneWidget);
    });

    testWidgets('DisclaimerScreen requires checkbox', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var accepted = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DisclaimerScreen(
            services: services,
            onAccepted: () => accepted = true,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('não é um dispositivo médico'), findsOneWidget);
      final continueBtn = find.text('Concordo e continuar');
      expect(tester.widget<FilledButton>(find.ancestor(
        of: continueBtn,
        matching: find.byType(FilledButton),
      )).onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(accepted, isFalse);
    });

    testWidgets('SupportScreen embedded shows loading then body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SupportScreen(services: services, embedded: true),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Profile fetch fails without auth → error or empty support section.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('HealthPlatformService extras', () {
    test('PlatformGlucoseReading.externalId prefers uuid', () {
      final withUuid = PlatformGlucoseReading(
        glucoseMgdl: 100,
        recordedAt: DateTime.utc(2026, 1, 1),
        sourceName: 'Libre',
        uuid: 'abc',
      );
      expect(withUuid.externalId, 'abc');
      final without = PlatformGlucoseReading(
        glucoseMgdl: 100,
        recordedAt: DateTime.utc(2026, 1, 1, 12),
        sourceName: 'Libre',
        uuid: '  ',
      );
      expect(without.externalId, startsWith('health:Libre:'));
    });

    test('unsupported auth/history helpers return empty/false', () async {
      final service = HealthPlatformService();
      if (service.isSupportedPlatform) return;
      expect(await service.requestAuthorization(), isFalse);
      expect(await service.hasAuthorization(), isFalse);
      expect(await service.requestBackgroundAuthorization(), isFalse);
      expect(await service.glucoseHistory(), isEmpty);
      expect(await service.latestGlucose(), isNull);
      expect(
        await service.writeGlucose(
          glucoseMgdl: 100,
          recordedAt: DateTime.now(),
        ),
        isNull,
      );
      expect(
        await service.writeMealCarbs(
          carbohydratesG: 30,
          recordedAt: DateTime.now(),
          clientRecordId: 'c1',
        ),
        isFalse,
      );
      expect(await service.availability(), HealthPlatformAvailability.unsupported);
      await service.openInstallPage();
    });
  });

  test('Profile isSupporter statuses', () {
    expect(const Profile(id: 'u', supporterStatus: 'active').isSupporter, isTrue);
    expect(const Profile(id: 'u', supporterStatus: 'grace').isSupporter, isTrue);
    expect(const Profile(id: 'u', supporterStatus: 'none').isSupporter, isFalse);
  });
}
