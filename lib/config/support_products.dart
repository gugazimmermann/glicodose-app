/// Product IDs must match App Store Connect, Play Console, and RevenueCat.
class SupportProducts {
  SupportProducts._();

  static const entitlementId = 'supporter';

  static const support10 = 'support_10';
  static const support20 = 'support_20';
  static const support50 = 'support_50';
  static const support100 = 'support_100';

  /// Yearly plan priced like ten months of [support10].
  static const support10Annual = 'support_10_annual';

  /// Default plan shown as the primary purchase button.
  static const recommendedId = support10;

  /// Free introductory offer configured on [support10] in the stores.
  static const trialDays = 7;

  /// Monthly tiers, cheapest → highest (same subscription group in the stores).
  static const monthlyIds = [
    support10,
    support20,
    support50,
    support100,
  ];

  static const annualIds = [support10Annual];

  /// Everything [SupportService.loadPlans] looks up in the current offering.
  static const orderedIds = [...monthlyIds, ...annualIds];

  /// Approximate BRL face values for UI fallback before store prices load.
  static const fallbackMonthlyBrl = {
    support10: 10,
    support20: 20,
    support50: 50,
    support100: 100,
  };

  /// Face value of the annual plan (ten months of R$10).
  static const fallbackAnnualBrl = {support10Annual: 100};

  static bool isAnnual(String productId) => annualIds.contains(productId);

  static String displayLabel(String productId) {
    final annual = fallbackAnnualBrl[productId];
    if (annual != null) return 'R\$$annual/ano';
    final brl = fallbackMonthlyBrl[productId];
    if (brl == null) return productId;
    return 'R\$$brl/mês';
  }

  static bool isKnownProduct(String? productId) =>
      productId != null && orderedIds.contains(productId);

  /// Label for a free introductory period, or null when there is nothing to show.
  ///
  /// [eligible] false hides the offer (the store will not grant it). Null means
  /// unknown — Android always reports unknown — so a free intro attached to
  /// the product is still shown.
  static String? freeTrialLabel({
    required double price,
    required String periodUnit,
    required int periodNumberOfUnits,
    required int cycles,
    required bool? eligible,
  }) {
    if (eligible == false || price > 0 || periodUnit != 'day') return null;
    final periods = cycles < 1 ? 1 : cycles;
    final days = periodNumberOfUnits * periods;
    if (days < 1) return null;
    return days == 1 ? '1 dia grátis' : '$days dias grátis';
  }
}
