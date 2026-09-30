import 'package:flutter/material.dart';

import 'package:diabetes_app/theme/app_theme.dart';

/// Shown when someone opens Libre, Health, or the home widget without support.
class SupporterFeatureNotice extends StatelessWidget {
  const SupporterFeatureNotice({super.key, required this.onTap});

  static const message =
      'O apoio libera o LibreLinkUp em tempo real, o widget da tela inicial '
      'e o Apple Health ou Health Connect. A calculadora de dose continua '
      'gratuita.';

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.favorite_outline,
                color: AppColors.primaryDark,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: AppColors.primaryDark.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
