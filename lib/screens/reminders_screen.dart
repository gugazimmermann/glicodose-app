import 'package:flutter/material.dart';

import 'package:diabetes_app/services/reminder_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, required this.reminderService});

  final ReminderService reminderService;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  ReminderSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.reminderService.loadSettings();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickTime({required bool glucose}) async {
    final s = _settings!;
    final initial = TimeOfDay(
      hour: glucose ? s.glucoseHour : s.mealHour,
      minute: glucose ? s.glucoseMinute : s.mealMinute,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _settings = glucose
          ? s.copyWith(
              glucoseHour: picked.hour,
              glucoseMinute: picked.minute,
            )
          : s.copyWith(
              mealHour: picked.hour,
              mealMinute: picked.minute,
            );
    });
  }

  Future<void> _save() async {
    final s = _settings;
    if (s == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.reminderService.saveAndReschedule(s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lembretes atualizados')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                SectionCard(
                  title: 'Notificações diárias',
                  icon: Icons.notifications_active_outlined,
                  iconColor: AppColors.primary,
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Lembrete de glicemia'),
                        subtitle: Text(
                          'Horário: ${_fmt(_settings!.glucoseHour, _settings!.glucoseMinute)}',
                        ),
                        value: _settings!.glucoseEnabled,
                        onChanged: (v) => setState(
                          () => _settings =
                              _settings!.copyWith(glucoseEnabled: v),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _pickTime(glucose: true),
                          child: const Text('Alterar horário da glicemia'),
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Lembrete de refeição'),
                        subtitle: Text(
                          'Horário: ${_fmt(_settings!.mealHour, _settings!.mealMinute)}',
                        ),
                        value: _settings!.mealEnabled,
                        onChanged: (v) => setState(
                          () =>
                              _settings = _settings!.copyWith(mealEnabled: v),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _pickTime(glucose: false),
                          child: const Text('Alterar horário da refeição'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: 16),
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
                      : const Text('Salvar lembretes'),
                ),
              ],
            ),
    );
  }
}
