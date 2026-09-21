import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand colors (stable across light/dark).
class AppColors {
  static const primary = Color(0xFF2F7CC4);
  static const primaryDark = Color(0xFF1E5A94);
  static const accent = Color(0xFFE31C23);
  static const error = Color(0xFFB71C1C);
  static const warning = Color(0xFFE65100);
  static const success = Color(0xFF2E7D32);

  /// Light-only fallbacks (prefer [of] when a [BuildContext] is available).
  static const warningSoft = Color(0xFFFFF4E5);
  static const surface = Color(0xFFF3F6FA);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF121212);
  static const muted = Color(0xFF5A6570);
  static const primarySoft = Color(0xFFE8F1F9);
  static const hint = Color(0xFF90A4AE);

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
  }
}

/// Semantic surfaces/text that flip with brightness.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surface,
    required this.card,
    required this.ink,
    required this.muted,
    required this.hint,
    required this.primarySoft,
    required this.warningSoft,
    required this.errorSoft,
    required this.outline,
    required this.cardBorder,
    required this.inputFill,
    required this.navBarBackground,
    required this.grid,
    required this.dotStroke,
    required this.tooltipBg,
  });

  final Color surface;
  final Color card;
  final Color ink;
  final Color muted;
  final Color hint;
  final Color primarySoft;
  final Color warningSoft;
  final Color errorSoft;
  final Color outline;
  final Color cardBorder;
  final Color inputFill;
  final Color navBarBackground;
  final Color grid;
  final Color dotStroke;
  final Color tooltipBg;

  static const light = AppPalette(
    surface: Color(0xFFF3F6FA),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF121212),
    muted: Color(0xFF5A6570),
    hint: Color(0xFF90A4AE),
    primarySoft: Color(0xFFE8F1F9),
    warningSoft: Color(0xFFFFF4E5),
    errorSoft: Color(0xFFFFEBEE),
    outline: Color(0xFFC5D0DB),
    cardBorder: Color(0xFFE2E8F0),
    inputFill: Color(0xFFFFFFFF),
    navBarBackground: Color(0xFFFFFFFF),
    grid: Color(0xFFE2E8F0),
    dotStroke: Color(0xFFFFFFFF),
    tooltipBg: Color(0xFF1E5A94),
  );

  static const dark = AppPalette(
    surface: Color(0xFF121A22),
    card: Color(0xFF1C2630),
    ink: Color(0xFFF2F5F8),
    muted: Color(0xFFA8B3BD),
    hint: Color(0xFF7A8794),
    primarySoft: Color(0xFF243447),
    warningSoft: Color(0xFF3A2E1C),
    errorSoft: Color(0xFF3A2226),
    outline: Color(0xFF3A4654),
    cardBorder: Color(0xFF2A3542),
    inputFill: Color(0xFF24303C),
    navBarBackground: Color(0xFF1C2630),
    grid: Color(0xFF2A3542),
    dotStroke: Color(0xFF1C2630),
    tooltipBg: Color(0xFF2F7CC4),
  );

  @override
  AppPalette copyWith({
    Color? surface,
    Color? card,
    Color? ink,
    Color? muted,
    Color? hint,
    Color? primarySoft,
    Color? warningSoft,
    Color? errorSoft,
    Color? outline,
    Color? cardBorder,
    Color? inputFill,
    Color? navBarBackground,
    Color? grid,
    Color? dotStroke,
    Color? tooltipBg,
  }) {
    return AppPalette(
      surface: surface ?? this.surface,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      hint: hint ?? this.hint,
      primarySoft: primarySoft ?? this.primarySoft,
      warningSoft: warningSoft ?? this.warningSoft,
      errorSoft: errorSoft ?? this.errorSoft,
      outline: outline ?? this.outline,
      cardBorder: cardBorder ?? this.cardBorder,
      inputFill: inputFill ?? this.inputFill,
      navBarBackground: navBarBackground ?? this.navBarBackground,
      grid: grid ?? this.grid,
      dotStroke: dotStroke ?? this.dotStroke,
      tooltipBg: tooltipBg ?? this.tooltipBg,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hint: Color.lerp(hint, other.hint, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      navBarBackground: Color.lerp(navBarBackground, other.navBarBackground, t)!,
      grid: Color.lerp(grid, other.grid, t)!,
      dotStroke: Color.lerp(dotStroke, other.dotStroke, t)!,
      tooltipBg: Color.lerp(tooltipBg, other.tooltipBg, t)!,
    );
  }
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppPalette.light);

  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: palette.primarySoft,
      onPrimaryContainer: isDark ? AppColors.primary : AppColors.primaryDark,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      secondaryContainer: isDark ? const Color(0xFF3A2226) : const Color(0xFFFFE8E9),
      onSecondaryContainer: isDark ? const Color(0xFFFFB4B8) : AppColors.accent,
      tertiary: AppColors.primaryDark,
      onTertiary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.ink,
      surfaceContainerHighest: palette.card,
      outline: palette.outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.surface,
      extensions: [palette],
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.cardBorder),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: TextStyle(color: palette.muted),
        hintStyle: TextStyle(color: palette.hint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.navBarBackground,
        indicatorColor: palette.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.primary : palette.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primary : palette.muted,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primaryDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: palette.cardBorder),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        textColor: palette.ink,
        iconColor: palette.muted,
      ),
    );
  }
}
