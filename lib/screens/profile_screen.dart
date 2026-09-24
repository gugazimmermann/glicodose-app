import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/screens/health_import_screen.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/theme_preference_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/app_logo.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.services,
    this.isOnboarding = false,
    this.onSaved,
    this.embedded = false,
  });

  final AppServices services;
  final bool isOnboarding;
  final VoidCallback? onSaved;
  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  final _targetNightController = TextEditingController();
  final _isfController = TextEditingController();
  final _icInsulinController = TextEditingController(text: '1');
  final _icCarbsController = TextEditingController();
  final _insulinController = TextEditingController();
  final _basalInsulinController = TextEditingController();
  final _basalDoseController = TextEditingController();
  int _nightStartMinute = 1200;
  int _nightEndMinute = 359;
  String _timezone = AppTime.defaultLocationName;
  String _theme = 'system';
  DateTime? _disclaimerAcceptedAt;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _userId;
  String? _shareCode;
  String _diabetesType = Profile.diabetesType1;
  double _doseStep = 1;
  double _insulinDurationHours = 4;
  List<int> _basalTimesMinutes = [];
  bool _basalReminderEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.services.profileRevision.addListener(_onProfileRevision);
  }

  @override
  void dispose() {
    widget.services.profileRevision.removeListener(_onProfileRevision);
    _nameController.dispose();
    _targetController.dispose();
    _targetNightController.dispose();
    _isfController.dispose();
    _icInsulinController.dispose();
    _icCarbsController.dispose();
    _insulinController.dispose();
    _basalInsulinController.dispose();
    _basalDoseController.dispose();
    super.dispose();
  }

  void _onProfileRevision() {
    if (!mounted || _saving) return;
    unawaited(_load());
  }

  TimeOfDay _minuteToTime(int minute) =>
      TimeOfDay(hour: (minute ~/ 60) % 24, minute: minute % 60);

  int _timeToMinute(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatMinute(int minute) {
    final t = _minuteToTime(minute);
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickNightTime({required bool start}) async {
    final initial = _minuteToTime(start ? _nightStartMinute : _nightEndMinute);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _nightStartMinute = _timeToMinute(picked);
      } else {
        _nightEndMinute = _timeToMinute(picked);
      }
    });
  }

  Future<void> _addBasalTime() async {
    if (_basalTimesMinutes.length >= 2) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 22, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final minute = _timeToMinute(picked);
    if (_basalTimesMinutes.contains(minute)) return;
    setState(() {
      _basalTimesMinutes = [..._basalTimesMinutes, minute]..sort();
    });
  }

  Future<void> _pickBasalTime(int index) async {
    final initial = _minuteToTime(_basalTimesMinutes[index]);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final minute = _timeToMinute(picked);
    setState(() {
      final next = List<int>.from(_basalTimesMinutes);
      next[index] = minute;
      _basalTimesMinutes = next.toSet().toList()..sort();
    });
  }

  Future<void> _load() async {
    try {
      _userId = widget.services.auth.currentUser?.id;
      final profile = await widget.services.profile.fetchCurrent();
      if (profile != null) {
        _nameController.text = profile.fullName ?? '';
        _targetController.text = profile.targetGlucoseMgdl?.toString() ?? '';
        _targetNightController.text =
            profile.targetNightMgdl?.toString() ?? '';
        _isfController.text = profile.isfMgdlPerU == null
            ? ''
            : formatWhole(profile.isfMgdlPerU);
        _icInsulinController.text = '1';
        _icCarbsController.text = profile.icRatio == null
            ? ''
            : formatWhole(profile.icRatio);
        _insulinController.text = profile.rapidInsulinName ?? '';
        _nightStartMinute = profile.nightStartMinute;
        _nightEndMinute = profile.nightEndMinute;
        _timezone = profile.timezone;
        _theme = profile.theme;
        _disclaimerAcceptedAt = profile.disclaimerAcceptedAt;
        _shareCode = profile.shareCode;
        _diabetesType = profile.diabetesType ?? Profile.diabetesType1;
        _doseStep = profile.doseStep <= 0 ? 1 : profile.doseStep;
        _insulinDurationHours = profile.insulinDurationHours <= 0
            ? 4
            : profile.insulinDurationHours;
        _basalInsulinController.text = profile.basalInsulinName ?? '';
        _basalDoseController.text = profile.basalDoseU == null
            ? ''
            : formatWhole(profile.basalDoseU);
        _basalTimesMinutes = List<int>.from(profile.basalTimesMinutes);
        _basalReminderEnabled = profile.basalReminderEnabled;
      }
    } catch (e) {
      _error = userFacingError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onThemeChanged(String theme) async {
    setState(() => _theme = theme);
    await ThemePreferenceService.save(ThemePreferenceService.decode(theme));
    final userId = _userId;
    if (userId == null) return;
    try {
      final current =
          await widget.services.profile.fetchCurrent(applyTheme: false);
      if (current == null) return;
      await widget.services.profile.upsert(current.copyWith(theme: theme));
    } catch (_) {
      // Local theme already applied; profile sync retries on next save.
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userId == null) {
      setState(() => _error = 'Usuário não autenticado');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final basalDoseRaw = _basalDoseController.text.trim();
      final basalDoseU = basalDoseRaw.isEmpty
          ? null
          : double.parse(basalDoseRaw.replaceAll(',', '.'));
      final current =
          await widget.services.profile.fetchCurrent(applyTheme: false);
      final base = current ?? Profile(id: _userId!);
      final profile = base.copyWith(
        fullName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        diabetesType: _diabetesType,
        targetGlucoseMgdl: int.parse(_targetController.text.trim()),
        targetNightMgdl: int.parse(_targetNightController.text.trim()),
        nightStartMinute: _nightStartMinute,
        nightEndMinute: _nightEndMinute,
        timezone: _timezone,
        theme: _theme,
        isfMgdlPerU:
            double.parse(_isfController.text.trim().replaceAll(',', '.')),
        icRatio: _parseIcRatio(),
        rapidInsulinName: _insulinController.text.trim(),
        doseStep: _doseStep,
        insulinDurationHours: _insulinDurationHours,
        basalInsulinName: _basalInsulinController.text.trim().isEmpty
            ? null
            : _basalInsulinController.text.trim(),
        clearBasalInsulinName: _basalInsulinController.text.trim().isEmpty,
        basalDoseU: basalDoseU,
        clearBasalDoseU: basalDoseU == null,
        basalTimesMinutes: _basalTimesMinutes,
        basalReminderEnabled: _basalReminderEnabled,
        disclaimerAcceptedAt: _disclaimerAcceptedAt,
      );
      await widget.services.profile.upsert(profile);
      await widget.services.reminders.syncBasalFromProfile(
        enabled: profile.basalReminderEnabled,
        timesMinutes: profile.basalTimesMinutes,
        timezone: profile.timezone,
        insulinName: profile.basalInsulinName,
        doseU: profile.basalDoseU,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo')),
      );
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else if (!widget.isOnboarding && !widget.embedded) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final form = _loading
        ? Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                if (widget.isOnboarding) ...[
                  Center(child: AppLogo(size: 88, showTitle: true)),
                  SizedBox(height: 12),
                  Text(
                    'Cadastre os fatores da sua prescrição. '
                    'A correção usa a meta do fuso horário do perfil.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted, height: 1.4),
                  ),
                  SizedBox(height: 20),
                ] else ...[
                  Row(
                    children: [
                      AppLogo(size: 40),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sua prescrição',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: colors.ink,
                              ),
                            ),
                            Text(
                              'Fatores editáveis — cada perfil é individual',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                ],
                if (!widget.isOnboarding && _shareCode != null) ...[
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Código para o médico',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Compartilhe este código com seu médico para ele '
                          'acompanhar seu histórico.',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.muted,
                            height: 1.35,
                          ),
                        ),
                        SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colors.outline,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _shareCode!,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 4,
                                    color: AppColors.primaryDark,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copiar código',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: _shareCode!),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Código copiado'),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.copy_rounded,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome (opcional)',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _diabetesType,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de diabetes',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: Profile.diabetesType1,
                            child: Text('Tipo 1'),
                          ),
                          DropdownMenuItem(
                            value: Profile.diabetesType2,
                            child: Text('Tipo 2'),
                          ),
                          DropdownMenuItem(
                            value: Profile.diabetesOther,
                            child: Text('Outro'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _diabetesType = v);
                        },
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _targetController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Meta de glicemia — dia (mg/dL)',
                          hintText: 'Ex: 110',
                          prefixIcon: Icon(
                            Icons.water_drop,
                            color: AppColors.accent,
                          ),
                        ),
                        validator: _requiredInt,
                      ),
                      SizedBox(height: 14),
                      TextFormField(
                        controller: _targetNightController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Meta noturna (mg/dL)',
                          hintText: 'Ex: 120',
                          prefixIcon: Icon(Icons.nightlight_round),
                        ),
                        validator: _requiredInt,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Fuso horário',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Usado para meta dia/noite, histórico e recomendações.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.muted,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: AppTime.curatedLocations
                                .any((e) => e.id == _timezone)
                            ? _timezone
                            : AppTime.defaultLocationName,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.public),
                        ),
                        items: [
                          for (final z in AppTime.curatedLocations)
                            DropdownMenuItem(
                              value: z.id,
                              child: Text(
                                z.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _timezone = v);
                        },
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Período noturno (fuso do perfil)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'A correção usa a meta conforme o horário neste fuso.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.muted,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickNightTime(start: true),
                              icon: const Icon(Icons.bedtime_outlined),
                              label: Text(
                                'Início ${_formatMinute(_nightStartMinute)}',
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickNightTime(start: false),
                              icon: const Icon(Icons.wb_twilight_outlined),
                              label: Text(
                                'Fim ${_formatMinute(_nightEndMinute)}',
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14),
                      TextFormField(
                        controller: _isfController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Fator de sensibilidade à insulina',
                          hintText: 'Ex: 150',
                          helperText: 'mg/dL que 1U de insulina reduz',
                          prefixIcon: Icon(Icons.science_outlined),
                        ),
                        validator: _requiredPositiveDouble,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Unidade de insulina / gramas de carboidratos',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _icInsulinController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Unidade de insulina',
                                hintText: 'Ex: 1',
                                prefixIcon: Icon(Icons.medication_outlined),
                              ),
                              validator: _requiredPositiveDouble,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(top: 16, left: 8, right: 8),
                            child: Text(
                              '/',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: colors.ink,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _icCarbsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Gramas de carboidratos',
                                hintText: 'Ex: 25',
                                prefixIcon: Icon(Icons.restaurant_outlined),
                              ),
                              validator: _requiredPositiveDouble,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14),
                      TextFormField(
                        controller: _insulinController,
                        decoration: const InputDecoration(
                          labelText: 'Insulina rápida',
                          hintText: 'Ex: Humalog, NovoRapid',
                          prefixIcon: Icon(Icons.vaccines_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe a insulina rápida';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Passo de dose (U)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [0.5, 1.0].map((step) {
                          final selected = (_doseStep - step).abs() < 0.001;
                          return ChoiceChip(
                            label: Text(step == 1 ? '1 U' : '0,5 U'),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _doseStep = step),
                            selectedColor: colors.primarySoft,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AppColors.primaryDark
                                  : colors.ink,
                            ),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Duração da insulina rápida: '
                        '${_insulinDurationHours.toStringAsFixed(1)} h',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Usada no cálculo de IOB (insulina ainda ativa).',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.muted,
                          height: 1.35,
                        ),
                      ),
                      Slider(
                        value: _insulinDurationHours.clamp(2, 8),
                        min: 2,
                        max: 8,
                        divisions: 12,
                        label: '${_insulinDurationHours.toStringAsFixed(1)} h',
                        onChanged: (v) =>
                            setState(() => _insulinDurationHours = v),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                SectionCard(
                  title: 'Insulina basal',
                  icon: Icons.nights_stay_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Registro e lembrete diário. Não entra no IOB da insulina rápida.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.muted,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _basalInsulinController,
                        decoration: const InputDecoration(
                          labelText: 'Insulina basal',
                          hintText: 'Ex: Lantus, Tresiba, NPH',
                          prefixIcon: Icon(Icons.vaccines_outlined),
                        ),
                      ),
                      SizedBox(height: 14),
                      TextFormField(
                        controller: _basalDoseController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Dose padrão (U)',
                          hintText: 'Ex: 18',
                          prefixIcon: Icon(Icons.straighten),
                        ),
                        validator: (value) {
                          final raw = value?.trim() ?? '';
                          if (raw.isEmpty) return null;
                          final n = double.tryParse(raw.replaceAll(',', '.'));
                          if (n == null || n <= 0) {
                            return 'Informe um valor positivo';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Horários (até 2)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _basalTimesMinutes.length; i++)
                            InputChip(
                              label: Text(_formatMinute(_basalTimesMinutes[i])),
                              onDeleted: () => setState(() {
                                _basalTimesMinutes =
                                    List<int>.from(_basalTimesMinutes)
                                      ..removeAt(i);
                                if (_basalTimesMinutes.isEmpty) {
                                  _basalReminderEnabled = false;
                                }
                              }),
                              onPressed: () => _pickBasalTime(i),
                            ),
                          if (_basalTimesMinutes.length < 2)
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 18),
                              label: const Text('Adicionar horário'),
                              onPressed: _addBasalTime,
                            ),
                        ],
                      ),
                      SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Lembrar diariamente'),
                        subtitle: Text(
                          _basalTimesMinutes.isEmpty
                              ? 'Adicione pelo menos um horário'
                              : 'Notificação local nos horários acima',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.muted,
                          ),
                        ),
                        value: _basalReminderEnabled,
                        onChanged: _basalTimesMinutes.isEmpty
                            ? null
                            : (v) =>
                                setState(() => _basalReminderEnabled = v),
                      ),
                    ],
                  ),
                ),
                if (!widget.isOnboarding) ...[
                  SizedBox(height: 16),
                  SectionCard(
                    title: 'Aparência',
                    icon: Icons.dark_mode_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Tema do app (sincroniza entre dispositivos)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.of(context).muted,
                            height: 1.35,
                          ),
                        ),
                        SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'system',
                              label: Text('Sistema'),
                              icon: Icon(Icons.brightness_auto, size: 18),
                            ),
                            ButtonSegment(
                              value: 'light',
                              label: Text('Claro'),
                              icon: Icon(Icons.light_mode_outlined, size: 18),
                            ),
                            ButtonSegment(
                              value: 'dark',
                              label: Text('Escuro'),
                              icon: Icon(Icons.dark_mode_outlined, size: 18),
                            ),
                          ],
                          selected: {_theme},
                          onSelectionChanged: (sel) {
                            if (sel.isEmpty) return;
                            _onThemeChanged(sel.first);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
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
                          widget.isOnboarding
                              ? 'Continuar'
                              : 'Salvar perfil',
                        ),
                ),
                if (!widget.isOnboarding) ...[
                  SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => HealthImportScreen(
                                  services: widget.services,
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Linkar Sensor'),
                  ),
                  SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            widget.services.selectedTabIndex.value = 2;
                          },
                    icon: const Icon(Icons.favorite_outline),
                    label: const Text('Apoiar o GlicoDose'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                  SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            await widget.services.auth.signOut();
                          },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sair da conta'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ],
              ],
            ),
          );

    if (widget.embedded) {
      return form;
    }

    if (widget.isOnboarding) {
      return Scaffold(
        appBar: AppBar(
          title: const AppBarLogoTitle(title: 'Complete seu perfil'),
          automaticallyImplyLeading: false,
        ),
        body: form,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
      ),
      body: form,
    );
  }

  double _parseIcRatio() {
    final units = double.parse(
      _icInsulinController.text.trim().replaceAll(',', '.'),
    );
    final carbs = double.parse(
      _icCarbsController.text.trim().replaceAll(',', '.'),
    );
    return carbs / units;
  }

  String? _requiredInt(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obrigatório';
    final n = int.tryParse(value.trim());
    if (n == null || n <= 0) return 'Número inválido';
    return null;
  }

  String? _requiredPositiveDouble(String? value) {
    if (value == null || value.trim().isEmpty) return 'Obrigatório';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null || n <= 0) return 'Número inválido';
    return null;
  }
}
