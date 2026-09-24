import 'dart:async';

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
    try {
      final profile = await widget.services.profile.fetchCurrent();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {}
  }

  @override
  void dispose() {
    _appliedController.dispose();
    _carbsController.dispose();
    super.dispose();
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
        confianca: _rec.confianca,
        observacao: 'Recálculo local após ajuste de carboidratos.',
      );
      final updated = await widget.services.entries.updateEntry(
        _entry.copyWith(
          recommendedInsulin: next.insulinaRecomendadaU,
        ).copyWithRaw(next.raw),
      );
      if (!mounted) return;
      setState(() {
        _rec = next;
        _entry = updated;
        if (!_confirmed) {
          _appliedController.text = formatWhole(next.insulinaRecomendadaU);
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
      final profile =
          await widget.services.profile.fetchCurrent(applyTheme: false);
      if (profile?.healthSyncEnabled != true) return;
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
      await health.writeInsulin(
        units: applied,
        recordedAt: at,
        basal: false,
      );
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

      // Best-effort Health write-back (insulin iOS-only; carbs both).
      unawaited(_writeHealthAfterConfirm(applied));

      if (!mounted) return;
      setState(() => _entry = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasUnconfirmed
                ? 'Dose confirmada. Lembrete de checagem em 2 h.'
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
        title: Text(widget.fromHistory ? 'Detalhe da dose' : 'Resultado da dose'),
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
                          text: formatWhole(_rec.insulinaRecomendadaU),
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
                        color: _confidenceColor(_rec.confianca)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _confidenceColor(_rec.confianca)
                              .withValues(alpha: 0.45),
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
                          'IOB descontado: ${formatWhole(_rec.iobU)} U '
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
                      value: '${formatWhole(_rec.carboidratosG)} g',
                    ),
                    SizedBox(width: 8),
                    _MetricChip(
                      label: 'Correção',
                      value: '${formatWhole(_rec.correcaoU)} U',
                    ),
                    SizedBox(width: 8),
                    _MetricChip(
                      label: 'Comida',
                      value: '${formatWhole(_rec.bolusComidaU)} U',
                    ),
                  ],
                ),
                if (_rec.observacao != null && _rec.observacao!.isNotEmpty) ...[
                  SizedBox(height: 12),
                  Text(
                    _rec.observacao!,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
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
                      helperText: 'Recalcula a dose com sua fórmula, sem IA',
                      prefixIcon: Icon(Icons.restaurant_outlined),
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
            OutlinedButton(
              onPressed: _newDose,
              child: const Text('Nova dose'),
            )
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

extension on Entry {
  Entry copyWithRaw(Map<String, dynamic>? raw) {
    return Entry(
      id: id,
      userId: userId,
      recordedAt: recordedAt,
      glucoseMgdl: glucoseMgdl,
      foodText: foodText,
      foodImagePath: foodImagePath,
      recommendedInsulin: recommendedInsulin,
      appliedInsulin: appliedInsulin,
      gptRawResponse: raw ?? gptRawResponse,
      createdAt: createdAt,
    );
  }
}
