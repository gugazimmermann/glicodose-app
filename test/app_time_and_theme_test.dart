import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/theme_preference_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTime', () {
    setUp(() {
      AppTime.ensureInitialized();
      AppTime.setLocation(AppTime.defaultLocationName);
    });

    test('labelFor curated and unknown', () {
      expect(AppTime.labelFor('America/Sao_Paulo'), contains('Brasília'));
      expect(AppTime.labelFor('Asia/Tokyo'), 'Asia/Tokyo');
      expect(AppTime.locationName, AppTime.defaultLocationName);
    });

    test('setLocation falls back on empty/invalid', () {
      AppTime.setLocation('  ');
      expect(AppTime.locationName, AppTime.defaultLocationName);
      AppTime.setLocation('Not/A/Zone');
      expect(AppTime.locationName, AppTime.defaultLocationName);
      AppTime.setLocation('Europe/Lisbon');
      expect(AppTime.locationName, 'Europe/Lisbon');
      expect(AppTime.now(), isNotNull);
    });

    test('format helpers', () {
      AppTime.setLocation('America/Sao_Paulo');
      final instant = DateTime.utc(2026, 9, 21, 15, 30);
      expect(AppTime.formatDateTime(instant), matches(RegExp(r'\d{2}/\d{2}/2026 \d{2}:\d{2}')));
      expect(AppTime.formatDateShort(instant), matches(RegExp(r'\d{2}/\d{2}')));
      expect(AppTime.formatDateTimeShort(instant), contains('/'));
      final local = AppTime.fromUtc(instant);
      expect(AppTime.formatHm(local), matches(RegExp(r'\d{2}:\d{2}')));
      expect(AppTime.minuteOfDay(local), local.hour * 60 + local.minute);
      expect(AppTime.formatHm(), matches(RegExp(r'\d{2}:\d{2}')));
    });
  });

  group('AppTheme / AppPalette', () {
    test('light and dark themes expose palette extension', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      final lightPal = AppTheme.light.extension<AppPalette>();
      final darkPal = AppTheme.dark.extension<AppPalette>();
      expect(lightPal, isNotNull);
      expect(darkPal, isNotNull);
      expect(lightPal!.ink, AppPalette.light.ink);
      expect(darkPal!.surface, AppPalette.dark.surface);
    });

    test('AppPalette copyWith and lerp', () {
      final copied = AppPalette.light.copyWith(ink: const Color(0xFF000001));
      expect(copied.ink, const Color(0xFF000001));
      expect(copied.card, AppPalette.light.card);

      final lerped = AppPalette.light.lerp(AppPalette.dark, 0.5);
      expect(lerped, isA<AppPalette>());
      expect(AppPalette.light.lerp(null, 0.5), AppPalette.light);
    });

    testWidgets('AppColors.of falls back without extension', (tester) async {
      late AppPalette colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) {
              colors = AppColors.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(colors.ink, AppPalette.light.ink);
    });
  });

  group('ThemePreferenceService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ThemePreferenceService.mode.value = ThemeMode.system;
    });

    test('encode/decode', () {
      expect(ThemePreferenceService.encode(ThemeMode.light), 'light');
      expect(ThemePreferenceService.encode(ThemeMode.dark), 'dark');
      expect(ThemePreferenceService.encode(ThemeMode.system), 'system');
      expect(ThemePreferenceService.decode('light'), ThemeMode.light);
      expect(ThemePreferenceService.decode('dark'), ThemeMode.dark);
      expect(ThemePreferenceService.decode(null), ThemeMode.system);
      expect(ThemePreferenceService.decode('nope'), ThemeMode.system);
    });

    test('load and save round-trip', () async {
      await ThemePreferenceService.save(ThemeMode.dark, notifyNative: true);
      expect(ThemePreferenceService.mode.value, ThemeMode.dark);
      final loaded = await ThemePreferenceService.load();
      expect(loaded, ThemeMode.dark);
      await ThemePreferenceService.save(ThemeMode.light, notifyNative: false);
      expect(ThemePreferenceService.mode.value, ThemeMode.light);
      await ThemePreferenceService.applyNativeInterfaceStyle(ThemeMode.system);
    });
  });
}
