import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/theme/app_theme.dart';

import 'fakes/fake_app_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    AppTime.ensureInitialized();
    AppTime.setLocation(AppTime.defaultLocationName);
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'public-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> setLarge(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('ProfileGate shows onboarding when profile incomplete',
      (tester) async {
    await setLarge(tester);
    final fake = FakeAppServices.create(
      profile: Profile(id: FakeAppServices.userId),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileGate(services: fake.services),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continuar'), findsOneWidget);
  });

  testWidgets('ProfileGate shows disclaimer when not accepted', (tester) async {
    await setLarge(tester);
    final base = FakeAppServices.completeProfile();
    final fake = FakeAppServices.create(
      profile: base.copyWith(clearDisclaimer: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileGate(services: fake.services),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Concordo e continuar'), findsOneWidget);
  });

  testWidgets('ProfileGate shows MainShell when profile ready', (tester) async {
    await setLarge(tester);
    final fake = FakeAppServices.create();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileGate(services: fake.services),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dose'), findsWidgets);
    expect(find.text('Histórico'), findsWidgets);
    expect(find.text('Perfil'), findsWidgets);
  });

  testWidgets('ProfileGate error offers retry', (tester) async {
    await setLarge(tester);
    final fake = FakeAppServices.create();
    fake.profile.throwOnFetch = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileGate(services: fake.services),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsOneWidget);
    fake.profile.throwOnFetch = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Dose'), findsWidgets);
  });
}
