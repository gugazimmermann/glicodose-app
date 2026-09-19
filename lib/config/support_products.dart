/// Product IDs must match App Store Connect, Play Console, and RevenueCat.
class SupportProducts {
  SupportProducts._();

  static const entitlementId = 'supporter';

  static const support10 = 'support_10';
  static const support20 = 'support_20';
  static const support50 = 'support_50';
  static const support100 = 'support_100';

  /// Monthly tiers, cheapest → highest (same subscription group in the stores).
  static const orderedIds = [
    support10,
    support20,
    support50,
    support100,
  ];

  /// Approximate BRL face values for UI fallback before store prices load.
  static const fallbackMonthlyBrl = {
    support10: 10,
    support20: 20,
    support50: 50,
    support100: 100,
  };

  static String displayLabel(String productId) {
    final brl = fallbackMonthlyBrl[productId];
    if (brl == null) return productId;
    return 'R\$$brl/mês';
  }

  static bool isKnownProduct(String? productId) =>
      productId != null && orderedIds.contains(productId);
}
