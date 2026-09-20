import 'package:flutter/material.dart';

import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/widgets/section_card.dart';

/// Placeholder for Health Connect / Apple Health / CGM import (R4).
class HealthImportScreen extends StatelessWidget {
  const HealthImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saúde e CGM')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          SectionCard(
            title: 'Importação em breve',
            icon: Icons.monitor_heart_outlined,
            iconColor: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A próxima etapa (R4) vai permitir importar glicemias de:',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 12),
                const _Bullet('Health Connect (Android)'),
                const _Bullet('Apple Health / HealthKit (iOS)'),
                const _Bullet('Sensores CGM compatíveis (ex.: Libre via health)'),
                const SizedBox(height: 14),
                Text(
                  'Por enquanto, continue registrando no app. Exportar CSV/PDF '
                  'no Histórico já ajuda na consulta.',
                  style: TextStyle(
                    color: AppColors.muted.withValues(alpha: 0.95),
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
