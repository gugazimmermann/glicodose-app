import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/screens/dose_result_screen.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/decimal_input.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/app_logo.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.services,
    this.embedded = false,
  });

  final AppServices services;
  final bool embedded;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Entry>> _future;
  final Map<String, String?> _photoUrls = {};

  @override
  void initState() {
    super.initState();
    _reload();
    widget.services.entriesRevision.addListener(_onEntriesChanged);
  }

  @override
  void dispose() {
    widget.services.entriesRevision.removeListener(_onEntriesChanged);
    super.dispose();
  }

  void _onEntriesChanged() {
    if (!mounted) return;
    setState(_reload);
  }

  void _reload() {
    _future = widget.services.entries.listEntries();
    _photoUrls.clear();
  }

  Future<String?> _photoUrl(Entry entry) async {
    final path = entry.foodImagePath;
    if (path == null || path.isEmpty) return null;
    if (_photoUrls.containsKey(entry.id)) return _photoUrls[entry.id];
    try {
      final url = await widget.services.entries.createSignedUrl(path);
      _photoUrls[entry.id] = url;
      return url;
    } catch (_) {
      _photoUrls[entry.id] = null;
      return null;
    }
  }

  Future<void> _openDetail(Entry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DoseResultScreen(
          services: widget.services,
          entry: entry,
          recommendation: InsulinRecommendation.fromEntry(entry),
          fromHistory: true,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _confirmDelete(Entry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover este registro?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.services.entries.deleteEntry(entry.id);
      widget.services.notifyEntriesChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro removido')),
      );
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _editEntry(Entry entry) async {
    final updated = await showModalBottomSheet<Entry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EditEntrySheet(entry: entry),
    );
    if (updated == null) return;
    try {
      await widget.services.entries.updateEntry(updated);
      widget.services.notifyEntriesChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro atualizado')),
      );
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final body = FutureBuilder<List<Entry>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userFacingError(snapshot.error!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(_reload),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }
        final entries = snapshot.data ?? [];
        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 72),
                  const SizedBox(height: 16),
                  const Text(
                    'Nenhum registro ainda',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Suas doses salvas aparecerão aqui.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => widget.services.selectedTabIndex.value = 0,
                    child: const Text('Registrar primeira dose'),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            setState(_reload);
            await _future;
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final food = (entry.foodText?.isNotEmpty == true)
                  ? entry.foodText!
                  : (entry.foodImagePath != null ? 'Foto anexada' : '—');
              final differs = entry.recommendedInsulin != null &&
                  entry.appliedInsulin != null &&
                  entry.recommendedInsulin != entry.appliedInsulin;
              final carbs = (entry.gptRawResponse?['carboidratos_g'] as num?)
                  ?.toDouble();
              final iob =
                  (entry.gptRawResponse?['iob_u'] as num?)?.toDouble();

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openDetail(entry),
                  child: SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${entry.glucoseMgdl}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                      height: 1,
                                    ),
                                  ),
                                  const Text(
                                    'mg/dL',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateFormat
                                        .format(entry.recordedAt.toLocal()),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      _DoseBadge(
                                        label: 'Recomendada',
                                        value: entry.recommendedInsulin,
                                      ),
                                      _DoseBadge(
                                        label: entry.appliedInsulin == null
                                            ? 'Aplicada'
                                            : 'Aplicada',
                                        value: entry.appliedInsulin,
                                        highlight: true,
                                        pending: entry.appliedInsulin == null,
                                        differs: differs,
                                      ),
                                    ],
                                  ),
                                  if (carbs != null || iob != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        if (carbs != null)
                                          'Carbs ${formatWhole(carbs)} g',
                                        if (iob != null)
                                          'IOB ${formatWhole(iob)} U',
                                      ].join(' · '),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _editEntry(entry);
                                if (value == 'delete') _confirmDelete(entry);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Editar'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                    ),
                                    title: Text('Excluir'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.foodImagePath != null) ...[
                              FutureBuilder<String?>(
                                future: _photoUrl(entry),
                                builder: (context, snap) {
                                  final url = snap.data;
                                  if (url == null) {
                                    return Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.image_outlined,
                                        color: AppColors.muted,
                                      ),
                                    );
                                  }
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      url,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 56,
                                        height: 56,
                                        color: AppColors.surface,
                                        child: const Icon(
                                          Icons.broken_image_outlined,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Text(
                                food,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.ink,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (differs) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Aplicada diferente da recomendada',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                        if (entry.appliedInsulin == null) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Aguardando confirmação da dose aplicada',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          IconButton(
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _EditEntrySheet extends StatefulWidget {
  const _EditEntrySheet({required this.entry});

  final Entry entry;

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  late final TextEditingController _glucose;
  late final TextEditingController _food;
  late final TextEditingController _applied;
  late DateTime _recordedAt;

  @override
  void initState() {
    super.initState();
    _glucose = TextEditingController(text: '${widget.entry.glucoseMgdl}');
    _food = TextEditingController(text: widget.entry.foodText ?? '');
    _applied = TextEditingController(
      text: widget.entry.appliedInsulin == null
          ? ''
          : formatWhole(widget.entry.appliedInsulin),
    );
    _recordedAt = widget.entry.recordedAt.toLocal();
  }

  @override
  void dispose() {
    _glucose.dispose();
    _food.dispose();
    _applied.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Editar registro',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _glucose,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Glicose (mg/dL)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _food,
            decoration: const InputDecoration(labelText: 'Alimentação'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _applied,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalInputFormatter],
            decoration: const InputDecoration(
              labelText: 'Insulina aplicada (U)',
              helperText: 'Deixe vazio se ainda não confirmou a dose',
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Data e hora'),
            subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(_recordedAt)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _recordedAt,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(_recordedAt),
              );
              if (time == null) return;
              setState(() {
                _recordedAt = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final glucose = int.tryParse(_glucose.text.trim());
              final appliedRaw = _applied.text.trim();
              final applied =
                  appliedRaw.isEmpty ? null : parseDecimal(appliedRaw);
              if (glucose == null || glucose <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Glicose inválida')),
                );
                return;
              }
              if (appliedRaw.isNotEmpty && applied == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Insulina aplicada inválida')),
                );
                return;
              }
              Navigator.pop(
                context,
                widget.entry.copyWith(
                  glucoseMgdl: glucose,
                  foodText: _food.text.trim(),
                  appliedInsulin: applied,
                  recordedAt: _recordedAt,
                ),
              );
            },
            child: const Text('Salvar alterações'),
          ),
        ],
      ),
    );
  }
}

class _DoseBadge extends StatelessWidget {
  const _DoseBadge({
    required this.label,
    required this.value,
    this.highlight = false,
    this.pending = false,
    this.differs = false,
  });

  final String label;
  final double? value;
  final bool highlight;
  final bool pending;
  final bool differs;

  @override
  Widget build(BuildContext context) {
    final bg = differs
        ? AppColors.warningSoft
        : highlight
            ? AppColors.primary
            : AppColors.surface;
    final fg = differs
        ? AppColors.warning
        : highlight
            ? Colors.white
            : AppColors.ink;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: differs
            ? Border.all(color: const Color(0xFFFFCC80))
            : null,
      ),
      child: Text(
        pending
            ? '$label —'
            : '$label ${value == null ? '—' : formatWhole(value)} U',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
