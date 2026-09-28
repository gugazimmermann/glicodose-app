import 'package:flutter/material.dart';

import 'package:diabetes_app/theme/app_theme.dart';

/// Warning shown when LibreLinkUp and the home widget are locked.
class SupporterFeatureNotice extends StatelessWidget {
  const SupporterFeatureNotice({super.key, required this.onTap});

  static const message =
      'Ao apoiar o GlicoDose, você pode usar o widget da tela inicial, '
      'o Health Connect ou o Apple Health e o monitoramento em tempo real '
      'com o LibreLinkUp.';

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: AppColors.warning.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
