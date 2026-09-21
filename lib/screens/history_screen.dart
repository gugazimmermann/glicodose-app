import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/screens/dose_result_screen.dart';
import 'package:diabetes_app/screens/history_charts_tab.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/entry_service.dart';
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

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tabs = TabBarView(
      controller: _tabController,
      children: [
        _HistoryListTab(services: widget.services),
        HistoryChartsTab(services: widget.services),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          Material(
            color: colors.card,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryDark,
              unselectedLabelColor: colors.muted,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Lista'),
                Tab(text: 'Gráficos'),
              ],
            ),
          ),
          Expanded(child: tabs),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Exportar',
            onSelected: (value) async {
              try {
                final entries =
                    await widget.services.entries.listEntries(limit: 500);
                final basalDoses =
                    await widget.services.basal.listDoses(limit: 500);
                if (value == 'csv') {
                  await widget.services.export.shareCsv(
                    entries,
                    basalDoses: basalDoses,
                  );
                } else if (value == 'report') {
                  final profile =
                      await widget.services.profile.fetchCurrent();
                  await widget.services.export.sharePdfLikeReport(
                    profile: profile,
                    entries: entries,
                    basalDoses: basalDoses,
                  );
                }
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(userFacingError(e))),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'csv', child: Text('Exportar CSV')),
              PopupMenuItem(
                value: 'report',
                child: Text('Relatório para consulta'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Lista'),
            Tab(text: 'Gráficos'),
          ],
        ),
      ),
      body: tabs,
    );
  }
}

class _HistoryListTab extends StatefulWidget {
  const _HistoryListTab({required this.services});

  final AppServices services;

  @override
  State<_HistoryListTab> createState() => _HistoryListTabState();
}

class _HistoryListTabState extends State<_HistoryListTab> {
  late Future<_HistoryListData> _future;
  final Map<String, String?> _photoUrls = {};
  int _page = 0;

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
    setState(() {
      _page = 0;
      _reload();
    });
  }

  void _reload() {
    _future = _loadPage(_page);
    _photoUrls.clear();
  }

  Future<_HistoryListData> _loadPage(int page) async {
    final entriesPage =
        await widget.services.entries.listEntriesPage(page: page);
    final basals = await widget.services.basal.listDoses(limit: 200);
    final windowBasals = _basalsForPage(entriesPage, basals, page);
    return _HistoryListData(
      entriesPage: entriesPage,
      basalDoses: windowBasals,
    );
  }

  List<BasalDose> _basalsForPage(
    EntriesPage pageData,
    List<BasalDose> all,
    int page,
  ) {
    if (all.isEmpty) return const [];
    if (pageData.entries.isEmpty) {
      return page == 0 ? all.take(20).toList() : const [];
    }
    final newest = pageData.entries.first.recordedAt;
    final oldest = pageData.entries.last.recordedAt;
    // On first page also include basals newer than the newest bolus.
    final upper = page == 0
        ? DateTime.now().toUtc().add(const Duration(days: 1))
        : newest;
    return all
        .where(
          (b) =>
              !b.recordedAt.isBefore(oldest) && !b.recordedAt.isAfter(upper),
        )
        .toList();
  }

  void _goToPage(int page) {
    setState(() {
      _page = page;
      _reload();
    });
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
      await widget.services.entries.deleteEntry(
        entry.id,
        foodImagePath: entry.foodImagePath,
      );
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

  Future<void> _confirmDeleteBasal(BasalDose dose) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover basal?'),
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
      await widget.services.basal.deleteDose(dose.id);
      widget.services.notifyEntriesChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Basal removida')),
      );
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _editBasal(BasalDose dose) async {
    final updated = await showModalBottomSheet<BasalDose>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EditBasalSheet(dose: dose),
    );
    if (updated == null) return;
    try {
      await widget.services.basal.updateDose(updated);
      widget.services.notifyEntriesChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Basal atualizada')),
      );
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  List<_TimelineItem> _mergeTimeline(
    List<Entry> entries,
    List<BasalDose> basals,
  ) {
    final items = <_TimelineItem>[
      ...entries.map(_TimelineItem.bolus),
      ...basals.map(_TimelineItem.basal),
    ];
    items.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FutureBuilder<_HistoryListData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
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
                  SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(_reload),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data!;
        final pageData = data.entriesPage;
        final entries = pageData.entries;
        final timeline = _mergeTimeline(entries, data.basalDoses);

        if (pageData.total == 0 && data.basalDoses.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 72),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum registro ainda',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Suas doses salvas aparecerão aqui.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted),
                  ),
                  SizedBox(height: 20),
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
            setState(() {
              _page = 0;
              _reload();
            });
            await _future;
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            itemCount: timeline.length + 1,
            separatorBuilder: (_, index) {
              if (index >= timeline.length - 1) return const SizedBox.shrink();
              return SizedBox(height: 12);
            },
            itemBuilder: (context, index) {
              if (index == timeline.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      Text(
                        'Página ${pageData.page + 1} de ${pageData.totalPages}'
                        ' · ${pageData.total} bolus'
                        '${data.basalDoses.isEmpty ? '' : ' · ${data.basalDoses.length} basal'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pageData.hasPrev
                                  ? () => _goToPage(pageData.page - 1)
                                  : null,
                              child: const Text('Anterior'),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pageData.hasNext
                                  ? () => _goToPage(pageData.page + 1)
                                  : null,
                              child: const Text('Próxima'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              final item = timeline[index];
              if (item.isBasal) {
                return _buildBasalCard(colors, item.basal!);
              }
              return _buildBolusCard(colors, item.entry!);
            },
          ),
        );
      },
    );
  }

  Widget _buildBasalCard(AppPalette colors, BasalDose dose) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.nights_stay_outlined, color: colors.ink),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primarySoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Basal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppTime.formatDateTime(dose.recordedAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '${formatWhole(dose.units)} U'
                  '${dose.insulinName != null && dose.insulinName!.trim().isNotEmpty ? ' · ${dose.insulinName}' : ''}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editBasal(dose);
              if (value == 'delete') _confirmDeleteBasal(dose);
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
    );
  }

  Widget _buildBolusCard(AppPalette colors, Entry entry) {
    final food = (entry.foodText?.isNotEmpty == true)
        ? entry.foodText!
        : (entry.foodImagePath != null ? 'Foto anexada' : '—');
    final differs = entry.recommendedInsulin != null &&
        entry.appliedInsulin != null &&
        entry.recommendedInsulin != entry.appliedInsulin;
    final carbs =
        (entry.gptRawResponse?['carboidratos_g'] as num?)?.toDouble();
    final iob = (entry.gptRawResponse?['iob_u'] as num?)?.toDouble();

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
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${entry.glucoseMgdl}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.ink,
                            height: 1,
                          ),
                        ),
                        Text(
                          'mg/dL',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppTime.formatDateTime(entry.recordedAt),
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _DoseBadge(
                              label: 'Recomendada',
                              value: entry.recommendedInsulin,
                            ),
                            _DoseBadge(
                              label: 'Aplicada',
                              value: entry.appliedInsulin,
                              highlight: true,
                              pending: entry.appliedInsulin == null,
                              differs: differs,
                            ),
                          ],
                        ),
                        if (carbs != null || iob != null) ...[
                          SizedBox(height: 6),
                          Text(
                            [
                              if (carbs != null)
                                'Carbs ${formatWhole(carbs)} g',
                              if (iob != null) 'IOB ${formatWhole(iob)} U',
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.muted,
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
              SizedBox(height: 12),
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
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.image_outlined,
                              color: colors.muted,
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
                              color: colors.surface,
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      food,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.ink,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              if (differs) ...[
                SizedBox(height: 8),
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
                SizedBox(height: 8),
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
  }
}

class _HistoryListData {
  const _HistoryListData({
    required this.entriesPage,
    required this.basalDoses,
  });

  final EntriesPage entriesPage;
  final List<BasalDose> basalDoses;
}

class _TimelineItem {
  const _TimelineItem.bolus(this.entry) : basal = null;

  const _TimelineItem.basal(this.basal) : entry = null;

  final Entry? entry;
  final BasalDose? basal;

  bool get isBasal => basal != null;

  DateTime get recordedAt =>
      basal?.recordedAt ?? entry!.recordedAt;
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
    _recordedAt = AppTime.fromUtc(widget.entry.recordedAt);
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
          SizedBox(height: 16),
          TextField(
            controller: _glucose,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Glicose (mg/dL)'),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _food,
            decoration: const InputDecoration(labelText: 'Alimentação'),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _applied,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalInputFormatter],
            decoration: const InputDecoration(
              labelText: 'Insulina aplicada (U)',
              helperText: 'Deixe vazio se ainda não confirmou a dose',
            ),
          ),
          SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Data e hora'),
            subtitle: Text(AppTime.formatDateTime(_recordedAt)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _recordedAt,
                firstDate: DateTime(2020),
                lastDate: AppTime.now().add(const Duration(days: 1)),
              );
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(_recordedAt),
              );
              if (time == null) return;
              setState(() {
                _recordedAt = tz.TZDateTime(
                  AppTime.location,
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            },
          ),
          SizedBox(height: 12),
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
                  recordedAt: _recordedAt.toUtc(),
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
    final colors = AppColors.of(context);
    final bg = differs
        ? colors.warningSoft
        : highlight
            ? AppColors.primary
            : colors.surface;
    final fg = differs
        ? AppColors.warning
        : highlight
            ? Colors.white
            : colors.ink;

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

class _EditBasalSheet extends StatefulWidget {
  const _EditBasalSheet({required this.dose});

  final BasalDose dose;

  @override
  State<_EditBasalSheet> createState() => _EditBasalSheetState();
}

class _EditBasalSheetState extends State<_EditBasalSheet> {
  late final TextEditingController _units;
  late final TextEditingController _name;
  late DateTime _recordedAt;

  @override
  void initState() {
    super.initState();
    _units = TextEditingController(text: formatWhole(widget.dose.units));
    _name = TextEditingController(text: widget.dose.insulinName ?? '');
    _recordedAt = AppTime.fromUtc(widget.dose.recordedAt);
  }

  @override
  void dispose() {
    _units.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _recordedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_recordedAt),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
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
            'Editar basal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Insulina',
              prefixIcon: Icon(Icons.vaccines_outlined),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _units,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalInputFormatter],
            decoration: const InputDecoration(
              labelText: 'Unidades (U)',
              prefixIcon: Icon(Icons.straighten),
            ),
          ),
          SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Data e horário'),
            subtitle: Text(AppTime.formatDateTime(_recordedAt)),
            trailing: TextButton(
              onPressed: _pickDateTime,
              child: const Text('Alterar'),
            ),
          ),
          SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final units = parseDecimal(_units.text);
              if (units == null || units <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dose inválida')),
                );
                return;
              }
              final name = _name.text.trim();
              Navigator.pop(
                context,
                widget.dose.copyWith(
                  units: units,
                  insulinName: name.isEmpty ? null : name,
                  clearInsulinName: name.isEmpty,
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
