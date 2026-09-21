import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and applies app theme mode (local cache + optional profile sync).
class ThemePreferenceService {
  ThemePreferenceService._();

  static const prefsKey = 'theme_mode';
  static const channel = MethodChannel('com.diabetes.diabetes_app/theme');

  /// Notifier owned by [DiabetesApp]; updated on load/save.
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static String encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final m = decode(prefs.getString(prefsKey));
    mode.value = m;
    await applyNativeInterfaceStyle(m);
    return m;
  }

  static Future<void> save(ThemeMode m, {bool notifyNative = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, encode(m));
    mode.value = m;
    if (notifyNative) {
      await applyNativeInterfaceStyle(m);
    }
  }

  /// Aligns iOS UIUserInterfaceStyle / Android day-night with [m].
  static Future<void> applyNativeInterfaceStyle(ThemeMode m) async {
    try {
      await channel
          .invokeMethod<void>('setThemeMode', encode(m))
          .timeout(const Duration(milliseconds: 300));
    } catch (_) {
      // Channel may be missing on web / tests.
    }
  }
}
