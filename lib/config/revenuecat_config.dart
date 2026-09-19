import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// RevenueCat public SDK keys via --dart-define / --dart-define-from-file.
///
/// ```env
/// REVENUECAT_IOS_API_KEY=appl_...
/// REVENUECAT_ANDROID_API_KEY=goog_...
/// ```
class RevenueCatConfig {
  static const String iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_API_KEY',
    defaultValue: '',
  );

  static const String androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
    defaultValue: '',
  );

  /// IAP only runs on Android/iOS (not web/desktop).
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  static String? get platformApiKey {
    if (!isSupportedPlatform) return null;
    if (Platform.isIOS) {
      return iosApiKey.isEmpty ? null : iosApiKey;
    }
    if (Platform.isAndroid) {
      return androidApiKey.isEmpty ? null : androidApiKey;
    }
    return null;
  }

  static bool get isConfigured =>
      isSupportedPlatform && platformApiKey != null;
}
