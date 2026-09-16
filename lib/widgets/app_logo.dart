import 'package:flutter/material.dart';

import 'package:diabetes_app/theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 96,
    this.showTitle = false,
    this.titleSize = 28,
    this.subtitle,
  });

  final double size;
  final bool showTitle;
  final double titleSize;
  final String? subtitle;

  static const assetPath = 'images/glucosemeter.png';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        if (showTitle) ...[
          SizedBox(height: size * 0.12),
          Text(
            'GlicoDose',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.muted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class AppBarLogoTitle extends StatelessWidget {
  const AppBarLogoTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          AppLogo.assetPath,
          width: 32,
          height: 32,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
