import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/config/support_products.dart';
import 'package:diabetes_app/models/profile.dart';

void main() {
  group('SupportProducts', () {
    test('ordered ids cover four monthly tiers', () {
      expect(SupportProducts.orderedIds, [
        'support_10',
        'support_20',
        'support_50',
        'support_100',
      ]);
      expect(SupportProducts.fallbackMonthlyBrl.values, [10, 20, 50, 100]);
    });

    test('displayLabel and isKnownProduct', () {
      expect(SupportProducts.displayLabel('support_20'), 'R\$20/mês');
      expect(SupportProducts.isKnownProduct('support_10'), isTrue);
      expect(SupportProducts.isKnownProduct('other'), isFalse);
    });

    test('entitlement id matches RevenueCat config', () {
      expect(SupportProducts.entitlementId, 'supporter');
    });
  });

  group('Profile supporter fields', () {
    test('fromJson reads supporter columns', () {
      final profile = Profile.fromJson({
        'id': '00000000-0000-4000-8000-000000000001',
        'supporter_product_id': 'support_50',
        'supporter_status': 'active',
        'supporter_store': 'apple',
      });
      expect(profile.supporterProductId, 'support_50');
      expect(profile.supporterStatus, 'active');
      expect(profile.supporterStore, 'apple');
      expect(profile.isSupporter, isTrue);
    });

    test('toJson does not include supporter_* (webhook-owned)', () {
      final profile = Profile(
        id: '00000000-0000-4000-8000-000000000001',
        supporterProductId: 'support_20',
        supporterStatus: 'active',
        supporterStore: 'google',
      );
      final json = profile.toJson();
      expect(json.containsKey('supporter_product_id'), isFalse);
      expect(json.containsKey('supporter_status'), isFalse);
      expect(json.containsKey('supporter_store'), isFalse);
    });

    test('canceled still counts as supporter until expiry UI', () {
      final profile = Profile(
        id: '00000000-0000-4000-8000-000000000001',
        supporterStatus: 'canceled',
      );
      expect(profile.isSupporter, isTrue);
      expect(
        Profile(
          id: '00000000-0000-4000-8000-000000000001',
          supporterStatus: 'expired',
        ).isSupporter,
        isFalse,
      );
    });
  });
}
