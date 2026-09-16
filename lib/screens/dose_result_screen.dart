import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class DoseResultScreen extends StatefulWidget {
  const DoseResultScreen({
    super.key,
    required this.services,
    required this.entry,
    required this.recommendation,
  });

  final AppServices services;
  final Entry entry;
  final InsulinRecommendation recommendation;

  @override
  State<DoseResultScreen> createState() => _DoseResultScreenState();
}

class _DoseResultScreenState extends State<DoseResultScreen> {
  late final TextEditingController _appliedController;
  late Entry _entry;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _appliedController = TextEditingController(
      text: formatWhole(
        _entry.appliedInsulin ?? widget.recommendation.insulinaRecomendadaU,
      ),
    );
  }

  @override
  void dispose() {
    _appliedController.dispose();
    super.dispose();
  }

  Future<void> _updateApplied() async {
    final applied = double.tryParse(
      _appliedController.text.trim().replaceAll(',', '.'),
    );
    if (applied == null) {
      setState(() => _error = 'Informe a insulina aplicada.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await widget.services.entries.updateEntry(
        _entry.copyWith(appliedInsulin: applied),
      );
      widget.services.notifyEntriesChanged();
      if (!mounted) return;
      setState(() => _entry = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dose aplicada atualizada')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recommendation;

    return Scaffold(
      appBar: AppBar(title: const Text('Resultado da dose')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          SectionCard(
            title: 'Insulina recomendada',
            icon: Icons.medication_outlined,
            iconColor: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: formatWhole(rec.insulinaRecomendadaU),
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            height: 1,
                          ),
                        ),
                        const TextSpan(
                          text: ' U',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    rec.source == 'manual'
                        ? 'Cálculo local (fórmula)'
                        : 'Carbs TACO (IA) + fórmula',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (rec.metaDisplay != null) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      rec.horarioBr != null
                          ? '${rec.metaDisplay!} · ${rec.horarioBr} (Brasília)'
                          : rec.metaDisplay!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MetricChip(
                      label: 'Carbs',
                      value: '${formatWhole(rec.carboidratosG)} g',
                    ),
                    const SizedBox(width: 8),
                    _MetricChip(
                      label: 'Correção',
                      value: '${formatWhole(rec.correcaoU)} U',
                    ),
                    const SizedBox(width: 8),
                    _MetricChip(
                      label: 'Comida',
                      value: '${formatWhole(rec.bolusComidaU)} U',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MetricChip(
                      label: 'IOB',
                      value: '${formatWhole(rec.iobU)} U',
                    ),
                  ],
                ),
                if (rec.observacao != null && rec.observacao!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    rec.observacao!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _appliedController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Insulina aplicada (U)',
                    helperText: 'Ajuste para mais ou menos se necessário',
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                  ),
                  onPressed: _saving ? null : _updateApplied,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Atualizar dose aplicada'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.accent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Nova dose'),
          ),
          const SizedBox(height: 8),
          Text(
            'Este cálculo já foi salvo no histórico.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.muted.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
