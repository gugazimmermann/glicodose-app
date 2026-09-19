import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/services/supporter_webhook_mapping.dart';

void main() {
  group('resolveSupporterStatus', () {
    test('purchase lifecycle → active', () {
      for (final type in [
        'INITIAL_PURCHASE',
        'RENEWAL',
        'UNCANCELLATION',
        'PRODUCT_CHANGE',
        'TEST',
      ]) {
        expect(resolveSupporterStatus(type), 'active', reason: type);
      }
    });

    test('billing / cancel / expire', () {
      expect(resolveSupporterStatus('BILLING_ISSUE'), 'grace');
      expect(resolveSupporterStatus('CANCELLATION'), 'canceled');
      expect(resolveSupporterStatus('EXPIRATION'), 'expired');
    });

    test('ignored events return null', () {
      expect(resolveSupporterStatus('SUBSCRIPTION_PAUSED'), isNull);
      expect(resolveSupporterStatus('TRANSFER'), isNull);
      expect(resolveSupporterStatus('UNKNOWN_EVENT'), isNull);
    });
  });

  group('mapStore', () {
    test('maps store enums', () {
      expect(mapStore('APP_STORE'), 'apple');
      expect(mapStore('PLAY_STORE'), 'google');
      expect(mapStore('STRIPE'), 'stripe');
      expect(mapStore('weird'), 'unknown');
    });
  });

  group('isSupabaseUserId', () {
    test('accepts uuid v4-ish', () {
      expect(
        isSupabaseUserId('00000000-0000-4000-8000-000000000001'),
        isTrue,
      );
      expect(isSupabaseUserId('\$RCAnonymousID:abc'), isFalse);
    });
  });
}
