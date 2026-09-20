import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/screens/health_import_screen.dart';
import 'package:diabetes_app/screens/reminders_screen.dart';
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
  int _nightStartMinute = 1200;
  int _nightEndMinute = 359;
  DateTime? _disclaimerAcceptedAt;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _userId;
  String? _shareCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _targetNightController.dispose();
    _isfController.dispose();
    _icInsulinController.dispose();
    _icCarbsController.dispose();
    _insulinController.dispose();
    super.dispose();
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
        _disclaimerAcceptedAt = profile.disclaimerAcceptedAt;
        _shareCode = profile.shareCode;
      }
    } catch (e) {
      _error = userFacingError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
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
      final profile = Profile(
        id: _userId!,
        fullName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        diabetesType: Profile.diabetesType1,
        targetGlucoseMgdl: int.parse(_targetController.text.trim()),
        targetNightMgdl: int.parse(_targetNightController.text.trim()),
        nightStartMinute: _nightStartMinute,
        nightEndMinute: _nightEndMinute,
        isfMgdlPerU:
            double.parse(_isfController.text.trim().replaceAll(',', '.')),
        icRatio: _parseIcRatio(),
        rapidInsulinName: _insulinController.text.trim(),
        doseStep: 1,
        insulinDurationHours: 4,
        disclaimerAcceptedAt: _disclaimerAcceptedAt,
      );
      await widget.services.profile.upsert(profile);
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
    final form = _loading
        ? const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                if (widget.isOnboarding) ...[
                  const Center(child: AppLogo(size: 88, showTitle: true)),
                  const SizedBox(height: 12),
                  const Text(
                    'Cadastre os fatores da sua prescrição. '
                    'A correção usa a meta do horário oficial de Brasília.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  const Row(
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
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              'Fatores editáveis — cada perfil é individual',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (!widget.isOnboarding && _shareCode != null) ...[
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Código para o médico',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Compartilhe este código com seu médico para ele '
                          'acompanhar seu histórico.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFC5D0DB),
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
                  const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 8),
                      const Text(
                        'Período noturno (horário de Brasília)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'A correção usa a meta do horário oficial de Brasília.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                          const SizedBox(width: 8),
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
                      const SizedBox(height: 14),
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
                      const SizedBox(height: 14),
                      const Text(
                        'Unidade de insulina / gramas de carboidratos',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                          const Padding(
                            padding: EdgeInsets.only(top: 16, left: 8, right: 8),
                            child: Text(
                              '/',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
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
                      const SizedBox(height: 14),
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
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
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
                          widget.isOnboarding
                              ? 'Continuar'
                              : 'Salvar perfil',
                        ),
                ),
                if (!widget.isOnboarding) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => RemindersScreen(
                                  reminderService: widget.services.reminders,
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Lembretes'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const HealthImportScreen(),
                              ),
                            );
                          },
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Saúde e CGM'),
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 12),
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
