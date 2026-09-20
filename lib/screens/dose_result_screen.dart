import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
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
  late final TextEditingController _carbsController;
  late Entry _entry;
  late InsulinRecommendation _rec;
  Profile? _profile;
  bool _saving = false;
  bool _recalculating = false;
  String? _error;

  bool get _confirmed => _entry.appliedInsulin != null;
  bool get _canAdjustCarbs =>
      !widget.fromHistory && _rec.source == 'ai' && !_confirmed;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _rec = widget.recommendation;
    _appliedController = TextEditingController(
      text: formatWhole(
        _entry.appliedInsulin ?? _rec.insulinaRecomendadaU,
      ),
    );
    _carbsController = TextEditingController(
      text: formatWhole(_rec.carboidratosG),
    );
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await widget.services.profile.fetchCurrent();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  @override
  void dispose() {
    _appliedController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  Future<void> _recalculateFromCarbs() async {
    final carbs = parseDecimal(_carbsController.text);
    if (carbs == null || carbs < 0) {
      setState(() => _error = 'Informe carboidratos válidos em gramas.');
      return;
    }
    final profile = _profile ?? await widget.services.profile.fetchCurrent();
    if (profile == null || !profile.isComplete) {
      setState(() => _error = 'Perfil incompleto para recalcular a dose.');
      return;
    }

    setState(() {
      _recalculating = true;
      _error = null;
    });

    try {
      final updated = widget.services.insulin.calculateManual(
        glucoseMgdl: _entry.glucoseMgdl,
        carboidratosG: carbs,
        profile: profile,
        iobU: _rec.iobU,
        observacao:
            'Carbs ajustados pelo usuário (estimativa IA original: '
            '${formatWhole(widget.recommendation.carboidratosG)} g, '
            'confiança ${widget.recommendation.confiancaLabel}).',
      );
      // Keep AI confidence label for transparency.
      final withConfidence = InsulinRecommendation(
        carboidratosG: updated.carboidratosG,
        correcaoU: updated.correcaoU,
        bolusComidaU: updated.bolusComidaU,
        insulinaRecomendadaU: updated.insulinaRecomendadaU,
        iobU: updated.iobU,
        observacao: updated.observacao,
        source: 'ai_adjusted',
        metaMgdl: updated.metaMgdl,
        metaPeriodo: updated.metaPeriodo,
        horarioBr: updated.horarioBr,
        confianca: widget.recommendation.confianca,
        raw: {
          ...?updated.raw,
          'confianca': widget.recommendation.confianca,
          'carbs_originais_ia': widget.recommendation.carboidratosG,
          'source': 'ai_adjusted',
        },
      );

      final saved = await widget.services.entries.updateEntry(
        _entry.copyWith(
          recommendedInsulin: withConfidence.insulinaRecomendadaU,
        ),
      );
      // Persist raw gpt response with adjustment metadata via a soft update
      // if the service supports it — updateEntry may not touch gpt_raw_response.
      widget.services.notifyEntriesChanged();

      if (!mounted) return;
      setState(() {
        _entry = saved;
        _rec = withConfidence;
        _appliedController.text = formatWhole(
          withConfidence.insulinaRecomendadaU,
        );
        _profile = profile;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
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

  Widget _warningBanner({
    required Color bg,
    required Color border,
    required Color iconColor,
    required IconData icon,
    required String text,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceLabel = switch (_rec.source) {
      'manual' => 'Cálculo local (sua fórmula)',
      'ai_adjusted' => 'Carbs ajustados + sua fórmula',
      _ => 'Estimativa de carbs (IA) + sua fórmula',
    };
    final isHypo = _entry.glucoseMgdl < 70;
    final doseZeroFromIob =
        _rec.iobU > 0 && _rec.insulinaRecomendadaU == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromHistory ? 'Detalhe da dose' : 'Resultado da dose'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (isHypo) ...[
            _warningBanner(
              bg: const Color(0xFFFFEBEE),
              border: const Color(0xFFEF9A9A),
              iconColor: AppColors.error,
              icon: Icons.warning_amber_rounded,
              text:
                  'Glicemia baixa (${_entry.glucoseMgdl} mg/dL). '
                  'Trate a hipoglicemia antes de aplicar insulina. '
                  'Siga a orientação do seu médico.',
              textColor: const Color(0xFFB71C1C),
            ),
            const SizedBox(height: 12),
          ],
          if (doseZeroFromIob) ...[
            _warningBanner(
              bg: AppColors.warningSoft,
              border: const Color(0xFFFFCC80),
              iconColor: AppColors.warning,
              icon: Icons.info_outline,
              text:
                  'Recomendação 0 U porque o IOB (${formatWhole(_rec.iobU)} U) '
                  'já cobre a dose bruta. Confirme com seu médico se precisa '
                  'aplicar alguma unidade.',
              textColor: const Color(0xFFBF360C),
            ),
            const SizedBox(height: 12),
          ],
          Semantics(
            label:
                'Insulina recomendada: ${formatWhole(_rec.insulinaRecomendadaU)} unidades',
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
                            text: formatWhole(_rec.insulinaRecomendadaU),
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
                  if (_rec.metaDisplay != null) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _rec.horarioBr != null
                            ? '${_rec.metaDisplay!} · ${_rec.horarioBr} (Brasília)'
                            : _rec.metaDisplay!,
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
                  _warningBanner(
                    bg: AppColors.warningSoft,
                    border: const Color(0xFFFFCC80),
                    iconColor: AppColors.warning,
                    icon: Icons.timelapse,
                    text:
                        'IOB descontado: ${formatWhole(_rec.iobU)} U '
                        '(insulina ainda ativa)',
                    textColor: const Color(0xFFBF360C),
                  ),
                  if (_canAdjustCarbs) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Carboidratos estimados pela IA'
                      '${_rec.confianca != null ? ' · confiança ${_rec.confiancaLabel}' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _carbsController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [decimalInputFormatter],
                            decoration: const InputDecoration(
                              labelText: 'Carbs (g)',
                              helperText: 'Ajuste se a estimativa estiver errada',
                              prefixIcon: Icon(Icons.restaurant_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: FilledButton.tonal(
                            onPressed:
                                _recalculating ? null : _recalculateFromCarbs,
                            child: _recalculating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Recalcular'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MetricChip(
                        label: 'Carbs',
                        value: '${formatWhole(_rec.carboidratosG)} g',
                      ),
                      const SizedBox(width: 8),
                      _MetricChip(
                        label: 'Correção',
                        value: '${formatWhole(_rec.correcaoU)} U',
                      ),
                      const SizedBox(width: 8),
                      _MetricChip(
                        label: 'Comida',
                        value: '${formatWhole(_rec.bolusComidaU)} U',
                      ),
                    ],
                  ),
                  if (_rec.observacao != null && _rec.observacao!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _rec.observacao!,
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
