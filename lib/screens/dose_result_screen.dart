import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/decimal_input.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class DoseResultScreen extends StatefulWidget {
  const DoseResultScreen({
    super.key,
    required this.services,
    required this.entry,
    required this.recommendation,
    this.fromHistory = false,
  });

  final AppServices services;
  final Entry entry;
  final InsulinRecommendation recommendation;
  final bool fromHistory;

  @override
  State<DoseResultScreen> createState() => _DoseResultScreenState();
}

class _DoseResultScreenState extends State<DoseResultScreen> {
  late final TextEditingController _appliedController;
  late Entry _entry;
  bool _saving = false;
  String? _error;

  bool get _confirmed => _entry.appliedInsulin != null;

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

  Future<void> _confirmApplied() async {
    final applied = parseDecimal(_appliedController.text);
    if (applied == null || applied < 0) {
      setState(() => _error = 'Informe a insulina que você aplicou.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final wasUnconfirmed = _entry.appliedInsulin == null;
      final updated = await widget.services.entries.updateEntry(
        _entry.copyWith(appliedInsulin: applied),
      );
      widget.services.notifyEntriesChanged();
      if (!mounted) return;
      setState(() => _entry = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasUnconfirmed
                ? 'Dose confirmada e salva no histórico'
                : 'Dose aplicada atualizada',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goHistory() {
    Navigator.of(context).pop(true);
    widget.services.goToHistoryTab();
  }

  void _newDose() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recommendation;
    final sourceLabel = rec.source == 'manual'
        ? 'Cálculo local (sua fórmula)'
        : 'Estimativa de carbs (IA) + sua fórmula';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromHistory ? 'Detalhe da dose' : 'Resultado da dose'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Semantics(
            label:
                'Insulina recomendada: ${formatWhole(rec.insulinaRecomendadaU)} unidades',
            child: SectionCard(
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
                      sourceLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFCC80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.timelapse,
                          color: AppColors.warning,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'IOB descontado: ${formatWhole(rec.iobU)} U '
                            '(insulina ainda ativa)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFBF360C),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [decimalInputFormatter],
                    decoration: InputDecoration(
                      labelText: 'Insulina aplicada (U)',
                      helperText: _confirmed
                          ? 'Ajuste se tomou uma dose diferente'
                          : 'Confirme a dose que você vai aplicar',
                      prefixIcon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                    ),
                    onPressed: _saving ? null : _confirmApplied,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _confirmed
                                ? 'Atualizar dose aplicada'
                                : 'Confirmar dose aplicada',
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          if (_confirmed) ...[
            FilledButton.tonal(
              onPressed: _goHistory,
              child: const Text('Ver no histórico'),
            ),
            const SizedBox(height: 8),
          ],
          if (!widget.fromHistory)
            OutlinedButton(
              onPressed: _newDose,
              child: const Text('Nova dose'),
            )
          else
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          const SizedBox(height: 10),
          Text(
            _confirmed
                ? 'Dose registrada como aplicada. Ela entra no cálculo de IOB.'
                : 'Recomendação salva. Confirme a dose aplicada para ela entrar no IOB.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.muted.withValues(alpha: 0.95),
              height: 1.35,
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
                fontSize: 12,
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
