import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/config/revenuecat_config.dart';
import 'package:diabetes_app/config/support_products.dart';
import 'package:diabetes_app/config/supabase_config.dart';
import 'package:diabetes_app/utils/decimal_input.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';

void main() {
  group('parseDecimal / dose_format', () {
    test('parseDecimal handles comma, empty and null', () {
      expect(parseDecimal(null), isNull);
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('  '), isNull);
      expect(parseDecimal('3,5'), 3.5);
      expect(parseDecimal('12.25'), 12.25);
      expect(parseDecimal('abc'), isNull);
    });

    test('decimalInputFormatter allows digits and separators', () {
      final old = TextEditingValue(text: '1');
      final ok = decimalInputFormatter.formatEditUpdate(
        old,
        const TextEditingValue(text: '1,5'),
      );
      expect(ok.text, '1,5');
      final rejected = decimalInputFormatter.formatEditUpdate(
        old,
        const TextEditingValue(text: '1a'),
      );
      expect(rejected.text, '1');
    });

    test('asWhole / asWholeDose / formatWhole edge cases', () {
      expect(asWhole(double.nan), 0);
      expect(asWhole(double.infinity), 0);
      expect(asWhole(2.6), 3);
      expect(asWholeDose(-1.2), 0);
      expect(asWholeDose(2.4), 2);
      expect(formatWhole(null), '—');
      expect(formatWhole(double.nan), '—');
      expect(formatWhole(4.6), '5');
    });
  });

  group('userFacingError', () {
    test('maps known error classes to Portuguese', () {
      expect(
        userFacingError(Exception('SocketException: failed host lookup')),
        contains('internet'),
      );
      expect(userFacingError('network timeout'), contains('internet'));
      expect(userFacingError('JWT expired / session'), contains('Sessão'));
      expect(userFacingError('401 Unauthorized'), contains('Sessão'));
      expect(userFacingError('perfil incompleto'), contains('Perfil'));
      expect(userFacingError('OpenAI estimar carbs'), contains('carboidratos'));
      expect(userFacingError('TimeoutException'), contains('demorou'));
      expect(userFacingError(Exception('boom')), 'boom');
      expect(userFacingError(Error()), isNotEmpty);
    });
  });

  group('config', () {
    test('SupabaseConfig and SupportProducts basics', () {
      expect(SupabaseConfig.url, isNotEmpty);
      expect(SupabaseConfig.anonKey, isNotEmpty);
      expect(SupportProducts.displayLabel('unknown_sku'), 'unknown_sku');
      expect(SupportProducts.isKnownProduct(null), isFalse);
      expect(SupportProducts.fallbackMonthlyBrl[SupportProducts.support10], 10);
    });

    test('RevenueCatConfig platform helpers on host', () {
      expect(RevenueCatConfig.iosApiKey, isA<String>());
      expect(RevenueCatConfig.androidApiKey, isA<String>());
      // Desktop/test host is not a store platform.
      expect(RevenueCatConfig.isSupportedPlatform, isFalse);
      expect(RevenueCatConfig.platformApiKey, isNull);
      expect(RevenueCatConfig.isConfigured, isFalse);
    });
  });
}
