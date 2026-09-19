import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:diabetes_app/config/revenuecat_config.dart';
import 'package:diabetes_app/config/support_products.dart';

class SupportPlanOption {
  const SupportPlanOption({
    required this.productId,
    required this.package,
    required this.priceLabel,
  });

  final String productId;
  final Package package;
  final String priceLabel;
}

class SupportService {
  SupportService();

  bool _configured = false;

  bool get isAvailable => RevenueCatConfig.isConfigured && _configured;

  Future<void> configure() async {
    if (!RevenueCatConfig.isConfigured) return;
    if (_configured) return;

    final apiKey = RevenueCatConfig.platformApiKey!;
    if (kDebugMode) {
      await Purchases.setLogLevel(LogLevel.debug);
    }
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _configured = true;
  }

  Future<void> logIn(String userId) async {
    if (!isAvailable) return;
    await Purchases.logIn(userId);
  }

  Future<void> logOut() async {
    if (!isAvailable) return;
    try {
      await Purchases.logOut();
    } on PlatformException catch (e) {
      // Already anonymous — ignore.
      debugPrint('Purchases.logOut: $e');
    }
  }

  Future<List<SupportPlanOption>> loadPlans() async {
    if (!isAvailable) return const [];

    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const [];

    final byId = <String, Package>{};
    for (final package in current.availablePackages) {
      byId[package.storeProduct.identifier] = package;
    }

    final plans = <SupportPlanOption>[];
    for (final id in SupportProducts.orderedIds) {
      final package = byId[id];
      if (package == null) continue;
      plans.add(
        SupportPlanOption(
          productId: id,
          package: package,
          priceLabel: package.storeProduct.priceString,
        ),
      );
    }
    return plans;
  }

  Future<CustomerInfo> purchase(Package package) async {
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return result.customerInfo;
  }

  Future<CustomerInfo> restore() async {
    return Purchases.restorePurchases();
  }

  Future<CustomerInfo> getCustomerInfo() async {
    return Purchases.getCustomerInfo();
  }

  bool hasActiveSupporter(CustomerInfo info) {
    return info.entitlements.active.containsKey(SupportProducts.entitlementId);
  }

  String? activeProductId(CustomerInfo info) {
    final entitlement =
        info.entitlements.active[SupportProducts.entitlementId];
    return entitlement?.productIdentifier;
  }

  Future<void> openManageSubscriptions({String? productId}) async {
    final Uri uri;
    if (!kIsWeb && Platform.isAndroid) {
      final packageName = 'com.diabetes.diabetes_app';
      final sku = productId ?? SupportProducts.support10;
      uri = Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?sku=$sku&package=$packageName',
      );
    } else {
      uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static String? purchaseErrorMessage(Object error) {
    if (error is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return null; // user cancelled — no snackbar needed
      }
      if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        return 'Você já possui um apoio ativo. Use Gerenciar assinatura '
            'para trocar de plano.';
      }
      return error.message ?? 'Não foi possível concluir a compra.';
    }
    return error.toString();
  }
}
