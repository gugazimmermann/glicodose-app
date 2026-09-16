import 'package:flutter/material.dart';

import 'package:diabetes_app/theme/app_theme.dart';

class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.accent, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Estimativa de bolus com base no seu perfil. '
              'Não substitui orientação médica.',
              style: TextStyle(
                color: AppColors.primaryDark,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
