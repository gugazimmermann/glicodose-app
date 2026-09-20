import 'package:flutter/material.dart';

import 'package:diabetes_app/config/revenuecat_config.dart';
import 'package:diabetes_app/theme/app_theme.dart';

/// Compact call-to-action that jumps to the Apoiar tab.
class SupportCtaBanner extends StatelessWidget {
  const SupportCtaBanner({
    super.key,
    required this.onTap,
    this.visible = true,
  });

  final VoidCallback onTap;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible || !RevenueCatConfig.isConfigured) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC5D0DB)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.favorite_outline,
                color: AppColors.primaryDark,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'O app é gratuito — apoie se puder. '
                  'Toque para ver os planos.',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 13,
                    height: 1.35,
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
