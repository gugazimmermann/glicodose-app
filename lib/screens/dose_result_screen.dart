import 'dart:async';

import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/content/clinical_disclaimer.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/fpu_bolus.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/decimal_input.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/food_recipe_editor.dart';
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
  late final TextEditingController _fatController;
  late final TextEditingController _proteinController;
  late Entry _entry;
  late InsulinRecommendation _rec;
  Profile? _profile;
  bool _saving = false;
  bool _recalculating = false;
  String? _error;

  bool get _confirmed => _entry.appliedInsulin != null;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _rec = widget.recommendation;
    _appliedController = TextEditingController(
      text: formatDose(_entry.appliedInsulin ?? _rec.insulinaRecomendadaU),
    );
    _carbsController = TextEditingController(
      text: formatQuantity(_rec.carboidratosG),
    );
    _fatController = TextEditingController(text: formatQuantity(_rec.gorduraG));
    _proteinController = TextEditingController(
      text: formatQuantity(_rec.proteinaG),
    );
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.services.profile.fetchCurrent();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {}
  }

  @override
  void dispose() {
    _appliedController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _proteinController.dispose();
    super.dispose();
  }

  Future<void> _saveRecipe() async {
    final saved = await showFoodRecipeEditor(
      context,
      recipes: widget.services.recipes,
      initialName: _entry.foodText?.trim() ?? '',
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Receita "${saved.name}" salva.')));
  }

  double? _optionalGramField(String text) {
    if (text.trim().isEmpty) return null;
    final value = parseDecimal(text);
    if (value == null || value < 0) return null;
    return value;
  }

  Color _confidenceColor(String? c) {
    switch (c) {
      case 'alta':
        return AppColors.success;
      case 'baixa':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _recalculateCarbs() async {
    final carbs = parseDecimal(_carbsController.text);
    if (carbs == null || carbs < 0) {
      setState(() => _error = 'Informe os carboidratos em gramas.');
      return;
    }
    final profile = _profile;
    if (profile == null || !profile.isComplete) {
      setState(() => _error = 'Perfil incompleto. Atualize sua prescrição.');
      return;
    }

    final fat = _optionalGramField(_fatController.text);
    final protein = _optionalGramField(_proteinController.text);
    if (fat == null && _fatController.text.trim().isNotEmpty) {
      setState(() => _error = 'Informe a gordura em gramas, ou deixe vazio.');
      return;
    }
    if (protein == null && _proteinController.text.trim().isNotEmpty) {
      setState(() => _error = 'Informe a proteína em gramas, ou deixe vazio.');
      return;
    }

    setState(() {
      _recalculating = true;
      _error = null;
    });

    try {
      final next = widget.services.insulin.recalculateWithCarbs(
        glucoseMgdl: _entry.glucoseMgdl,
        carboidratosG: carbs,
        profile: profile,
        iobU: _rec.iobU,
        gorduraG: fat,
        proteinaG: protein,
        confianca: _rec.confianca,
        observacao: 'Recálculo local após ajuste de carboidratos.',
      );
      final updated = await widget.services.entries.updateEntry(
        _entry.copyWith(
          recommendedInsulin: next.insulinaRecomendadaU,
          gptRawResponse: next.raw ?? _entry.gptRawResponse,
        ),
      );
      if (!mounted) return;
      setState(() {
        _rec = next;
        _entry = updated;
        if (!_confirmed) {
          _appliedController.text = formatDose(next.insulinaRecomendadaU);
        }
      });
      widget.services.notifyEntriesChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  Future<void> _writeHealthAfterConfirm(double applied) async {
    try {
      final profile = await widget.services.profile.fetchCurrent(
        applyTheme: false,
      );
      if (profile?.isSupporter != true || profile?.healthSyncEnabled != true) {
        return;
      }
      final health = widget.services.healthPlatform;
      final at = _entry.recordedAt;
      if (_rec.carboidratosG > 0) {
        final mealId = _entry.healthMealClientId ?? _entry.id;
        final ok = await health.writeMealCarbs(
          carbohydratesG: _rec.carboidratosG,
          recordedAt: at,
          clientRecordId: mealId,
          name: _entry.foodText,
        );
        if (ok && _entry.healthMealClientId == null) {
          await widget.services.entries.updateEntry(
            _entry.copyWith(healthMealClientId: mealId),
          );
        }
      }
      await health.writeInsulin(units: applied, recordedAt: at, basal: false);
    } catch (_) {}
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
      await widget.services.iobLive.refreshFromNetwork();
      await widget.services.reminders.schedulePostBolusCheck();
      final laterU = _rec.fpuLaterU;
      final laterHours = _rec.fpuLaterHours;
      if (laterU != null && laterU > 0 && laterHours != null) {
        await widget.services.reminders.scheduleFpuBolus(
          units: laterU,
          hours: laterHours,
        );
      }

      // Best-effort Health write-back (insulin iOS-only; carbs both).
      unawaited(_writeHealthAfterConfirm(applied));

      if (!mounted) return;
      setState(() => _entry = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasUnconfirmed
                ? (laterU != null && laterU > 0
                      ? 'Dose confirmada. Checagem em 2 h e segunda parte em $laterHours h.'
                      : 'Dose confirmada. Lembrete de checagem em 2 h.')
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
    final colors = AppColors.of(context);
    final sourceLabel = _rec.source == 'manual'
        ? 'Cálculo local (sua fórmula)'
        : _rec.source == 'local_adjust'
        ? 'Recálculo local (carbs ajustados)'
        : 'Estimativa de carbs (IA) + sua fórmula';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fromHistory ? 'Detalhe da dose' : 'Resultado da dose',
        ),
      ),
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
                          text: formatDose(_rec.insulinaRecomendadaU),
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            height: 1,
                          ),
                        ),
                        TextSpan(
                          text: ' U',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Center(
                  child: Text(
                    sourceLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_rec.confianca != null) ...[
                  SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _confidenceColor(
                          _rec.confianca,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _confidenceColor(
                            _rec.confianca,
                          ).withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        'Confiança nos carbs: ${_rec.confiancaLabel}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _confidenceColor(_rec.confianca),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_rec.metaDisplay != null) ...[
                  SizedBox(height: 6),
                  Center(
                    child: Text(
                      _rec.horarioBr != null
                          ? '${_rec.metaDisplay!} · ${_rec.horarioBr}'
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
                SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.warningSoft,
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
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'IOB descontado: ${formatDose(_rec.iobU)} U '
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
                SizedBox(height: 12),
                Row(
                  children: [
                    _MetricChip(
                      label: 'Carbs',
                      value: '${formatQuantity(_rec.carboidratosG)} g',
                    ),
                    SizedBox(width: 8),
                    _MetricChip(
                      label: 'Correção',
                      value: '${formatDose(_rec.correcaoU)} U',
                    ),
                    SizedBox(width: 8),
                    _MetricChip(
                      label: 'Comida',
                      value: '${formatDose(_rec.bolusComidaU)} U',
                    ),
                  ],
                ),
                if (_rec.gorduraG != null || _rec.proteinaG != null) ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      if (_rec.gorduraG != null)
                        _MetricChip(
                          label: 'Gordura',
                          value: '${formatQuantity(_rec.gorduraG)} g',
                        ),
                      if (_rec.gorduraG != null && _rec.proteinaG != null)
                        SizedBox(width: 8),
                      if (_rec.proteinaG != null)
                        _MetricChip(
                          label: 'Proteína',
                          value: '${formatQuantity(_rec.proteinaG)} g',
                        ),
                    ],
                  ),
                ],
                if (_rec.pesoG != null) ...[
                  SizedBox(height: 12),
                  Text(
                    'Peso estimado: ${_rec.pesoG} g',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                ],
                if (_rec.fpuLaterU != null &&
                    _rec.fpuLaterU! > 0 &&
                    _rec.fpuLaterHours != null) ...[
                  SizedBox(height: 12),
                  if (_rec.fpu != null)
                    Text(
                      '${formatQuantity(_rec.fpu)} FPU, '
                      '${formatQuantity(_rec.fpuEquivalentG)} g de carboidrato equivalente',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: colors.muted,
                      ),
                    ),
                  SizedBox(height: 4),
                  Text(
                    'Agora: ${formatDose(_rec.insulinaRecomendadaU)} U',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Depois: ${formatDose(_rec.fpuLaterU)} U daqui a ${_rec.fpuLaterHours} h',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Gordura e proteína atrasam a subida.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: colors.muted,
                    ),
                  ),
                ] else if (_rec.fpu != null &&
                    _rec.fpu! < FpuBolus.minFpu &&
                    (_rec.gorduraG != null || _rec.proteinaG != null)) ...[
                  SizedBox(height: 12),
                  Text(
                    'Gordura e proteína foram contadas '
                    '(${formatQuantity(_rec.fpu)} FPU). Sem segunda dose.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: colors.muted,
                    ),
                  ),
                ],
                if (_rec.observacao != null && _rec.observacao!.isNotEmpty) ...[
                  SizedBox(height: 12),
                  Text(
                    _rec.observacao!,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
                SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saveRecipe,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Salvar como receita'),
                  ),
                ),
                if (!widget.fromHistory || !_confirmed) ...[
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _carbsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [decimalInputFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Ajustar carboidratos (g)',
                      helperText:
                          'Recalcula a dose e a segunda de gordura, sem IA',
                      prefixIcon: Icon(Icons.restaurant_outlined),
                    ),
                  ),
                  SizedBox(height: 10),
                  TextFormField(
                    controller: _fatController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [decimalInputFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Ajustar gordura (g)',
                      helperText: 'Opcional. Vazio não conta gordura.',
                    ),
                  ),
                  SizedBox(height: 10),
                  TextFormField(
                    controller: _proteinController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [decimalInputFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Ajustar proteína (g)',
                      helperText: 'Opcional. Vazio não conta proteína.',
                    ),
                  ),
                  SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _recalculating ? null : _recalculateCarbs,
                    icon: _recalculating
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Recalcular com estes carbs'),
                  ),
                ],
                SizedBox(height: 16),
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
                SizedBox(height: 14),
                Text(
                  ClinicalDisclaimer.confirmHint,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colors.muted,
                  ),
                ),
                SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                  ),
                  onPressed: _saving ? null : _confirmApplied,
                  child: _saving
                      ? SizedBox(
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
          if (_error != null) ...[
            SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          SizedBox(height: 16),
          if (_confirmed) ...[
            FilledButton.tonal(
              onPressed: _goHistory,
              child: const Text('Ver no histórico'),
            ),
            SizedBox(height: 8),
          ],
          if (!widget.fromHistory)
            OutlinedButton(onPressed: _newDose, child: const Text('Nova dose'))
          else
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          SizedBox(height: 10),
          Text(
            _confirmed
                ? 'Dose registrada como aplicada. Ela entra no cálculo de IOB.'
                : 'Recomendação salva. Confirme a dose aplicada para ela entrar no IOB.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: colors.muted.withValues(alpha: 0.95),
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
    final colors = AppColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 2),
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
