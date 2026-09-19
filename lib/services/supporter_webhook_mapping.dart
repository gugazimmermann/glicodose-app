/// Pure helpers mirroring supabase/functions/revenuecat-webhook status mapping.
/// Kept in Dart so CI can validate webhook semantics without Deno.
library;

String? resolveSupporterStatus(String type) {
  switch (type) {
    case 'INITIAL_PURCHASE':
    case 'RENEWAL':
    case 'UNCANCELLATION':
    case 'PRODUCT_CHANGE':
    case 'SUBSCRIPTION_EXTENDED':
    case 'NON_RENEWING_PURCHASE':
    case 'TEMPORARY_ENTITLEMENT_GRANT':
    case 'REFUND_REVERSED':
    case 'TEST':
      return 'active';
    case 'BILLING_ISSUE':
      return 'grace';
    case 'CANCELLATION':
      return 'canceled';
    case 'EXPIRATION':
      return 'expired';
    case 'SUBSCRIPTION_PAUSED':
    case 'TRANSFER':
      return null;
    default:
      return null;
  }
}

String? mapStore(String? store) {
  if (store == null) return null;
  switch (store.toUpperCase()) {
    case 'APP_STORE':
    case 'MAC_APP_STORE':
      return 'apple';
    case 'PLAY_STORE':
      return 'google';
    case 'AMAZON':
      return 'amazon';
    case 'STRIPE':
      return 'stripe';
    case 'PROMOTIONAL':
      return 'promotional';
    default:
      return 'unknown';
  }
}

bool isSupabaseUserId(String value) {
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);
}
