import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/history_stats.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/section_card.dart';

class HistoryChartsTab extends StatefulWidget {
  const HistoryChartsTab({super.key, required this.services});

  final AppServices services;

  @override
  State<HistoryChartsTab> createState() => _HistoryChartsTabState();
}

class _HistoryChartsTabState extends State<HistoryChartsTab> {
  HistoryPeriod _period = HistoryPeriod.days30;
  late Future<_ChartsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.services.entriesRevision.addListener(_onEntriesChanged);
  }

  @override
  void dispose() {
    widget.services.entriesRevision.removeListener(_onEntriesChanged);
    super.dispose();
  }

  void _onEntriesChanged() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<_ChartsData> _load() async {
    final since = _period.since();
    final entriesFuture = since == null
        ? widget.services.entries.listEntries(limit: 200)
        : widget.services.entries.listEntriesSince(since);
    final basalFuture = since == null
        ? widget.services.basal.listDoses(limit: 200)
        : widget.services.basal.listSince(since);
    final glicemiasFuture = since == null
        ? widget.services.glicemias.listRecent(limit: 5000)
        : widget.services.glicemias.listSince(since);
    final profileFuture = widget.services.profile.fetchCurrent();
    final results = await Future.wait([
      entriesFuture,
      basalFuture,
      glicemiasFuture,
      profileFuture,
    ]);
    final entries = results[0] as List<Entry>;
    final basalDoses = results[1] as List<BasalDose>;
    final glucoseSamples = results[2] as List<GlucoseSample>;
    final profile = results[3] as Profile?;
    final chronological = [...entries]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final chartSamples = HistoryStats.downsample(glucoseSamples);
    final stats = HistoryStats.compute(
      entries: chronological,
      glucoseSamples: glucoseSamples,
      profile: profile,
    );
    final totalBasalU =
        basalDoses.fold<double>(0, (sum, b) => sum + b.units);
    return _ChartsData(
      entries: chronological,
      glucoseSamples: chartSamples,
      profile: profile,
      stats: stats,
      totalBasalU: totalBasalU,
      basalCount: basalDoses.length,
    );
  }

  void _setPeriod(HistoryPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FutureBuilder<_ChartsData>(
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
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!;
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            final next = _load();
            setState(() => _future = next);
            await next;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _PeriodChips(
                selected: _period,
                onSelected: _setPeriod,
              ),
              SizedBox(height: 16),
              if (data.entries.isEmpty &&
                  data.basalCount == 0 &&
                  data.glucoseSamples.isEmpty)
                SectionCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Sem dados no período',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: colors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else ...[
                _StatsSummary(
                  stats: data.stats,
                  totalBasalU: data.totalBasalU,
                  basalCount: data.basalCount,
                ),
                if (data.glucoseSamples.isNotEmpty ||
                    data.entries.isNotEmpty) ...[
                  SizedBox(height: 16),
                  _GlucoseChart(
                    samples: data.glucoseSamples.isNotEmpty
                        ? data.glucoseSamples
                        : data.entries
                            .map(
                              (e) => GlucoseSample(
                                glucoseMgdl: e.glucoseMgdl,
                                recordedAt: e.recordedAt,
                              ),
                            )
                            .toList(),
                    dayTarget: data.stats.dayTargetMgdl,
                  ),
                ],
                if (data.entries.isNotEmpty) ...[
                  SizedBox(height: 16),
                  _InsulinChart(entries: data.entries),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChartsData {
  const _ChartsData({
    required this.entries,
    required this.glucoseSamples,
    required this.profile,
    required this.stats,
    required this.totalBasalU,
    required this.basalCount,
  });

  final List<Entry> entries;
  final List<GlucoseSample> glucoseSamples;
  final Profile? profile;
  final HistoryStats stats;
  final double totalBasalU;
  final int basalCount;
}

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({
    required this.selected,
    required this.onSelected,
  });

  final HistoryPeriod selected;
  final ValueChanged<HistoryPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Wrap(
      spacing: 8,
      children: HistoryPeriod.values.map((p) {
        final isSelected = p == selected;
        return ChoiceChip(
          label: Text(p.label),
          selected: isSelected,
          onSelected: (_) => onSelected(p),
          selectedColor: colors.primarySoft,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.primaryDark : colors.ink,
          ),
          side: BorderSide(
            color: isSelected ? AppColors.primary : colors.outline,
          ),
        );
      }).toList(),
    );
  }
}

class _StatsSummary extends StatelessWidget {
  const _StatsSummary({
    required this.stats,
    required this.totalBasalU,
    required this.basalCount,
  });

  final HistoryStats stats;
  final double totalBasalU;
  final int basalCount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    String fmt1(double? v, {String suffix = ''}) {
      if (v == null) return '—';
      return '${formatWhole(v)}$suffix';
    }

    String fmtPct(double? v) {
      if (v == null) return '—';
      return '${v.round()}%';
    }

    String deltaLabel(double? v) {
      if (v == null) return '—';
      final sign = v > 0 ? '+' : '';
      return '$sign${formatWhole(v)} U';
    }

    return SectionCard(
      title: 'Resumo do período',
      icon: Icons.insights_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stats.count} registro${stats.count == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 13, color: colors.muted),
          ),
          SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: [
              _MetricTile(
                label: 'TIR 70–180',
                value: fmtPct(stats.tirPercent),
                hint: stats.tirPercent == null
                    ? null
                    : '${stats.tirCount} de ${stats.count}',
              ),
              _MetricTile(
                label: 'GMI (eA1c)',
                value: stats.gmiPercent == null
                    ? '—'
                    : '${stats.gmiPercent!.toStringAsFixed(1)}%',
                hint: 'Estimativa a partir da média',
              ),
              _MetricTile(
                label: 'Glicose média',
                value: fmt1(stats.avgGlucose, suffix: ' mg/dL'),
                hint: stats.minGlucose != null && stats.maxGlucose != null
                    ? '${stats.minGlucose}–${stats.maxGlucose} mg/dL'
                    : null,
              ),
              _MetricTile(
                label: 'Na meta (±20%)',
                value: fmtPct(stats.inTargetPercent),
                hint: stats.inTargetPercent == null
                    ? 'Cadastre a meta no perfil'
                    : '${stats.inTargetCount} de ${stats.count}',
              ),
              _MetricTile(
                label: 'Insulina rápida',
                value: fmt1(stats.totalAppliedU, suffix: ' U'),
                hint: stats.avgAppliedU == null
                    ? null
                    : 'Média ${formatWhole(stats.avgAppliedU)} U',
              ),
              _MetricTile(
                label: 'Basal aplicada',
                value: fmt1(totalBasalU, suffix: ' U'),
                hint: basalCount == 0
                    ? 'Sem registros de basal'
                    : '$basalCount registro${basalCount == 1 ? '' : 's'}',
              ),
              _MetricTile(
                label: 'Desvio vs recomendada',
                value: deltaLabel(stats.avgDoseDeltaU),
                hint: stats.doseDeltaCount == 0
                    ? 'Sem pares para comparar'
                    : 'Média rec. − aplicada',
              ),
              _MetricTile(
                label: 'Carbs médios',
                value: fmt1(stats.avgCarbsG, suffix: ' g'),
                hint: stats.carbsCount == 0
                    ? 'Sem estimativa TACO'
                    : '${stats.carbsCount} refeição${stats.carbsCount == 1 ? '' : 'ões'}',
              ),
              _MetricTile(
                label: 'Insulina recomendada',
                value: fmt1(stats.totalRecommendedU, suffix: ' U'),
                hint: '${stats.recommendedCount} dose${stats.recommendedCount == 1 ? '' : 's'}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: colors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: colors.ink,
            ),
          ),
          if (hint != null) ...[
            SizedBox(height: 4),
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: colors.hint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlucoseChart extends StatelessWidget {
  const _GlucoseChart({
    required this.samples,
    this.dayTarget,
  });

  final List<GlucoseSample> samples;
  final int? dayTarget;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final spots = <FlSpot>[];
    for (var i = 0; i < samples.length; i++) {
      spots.add(FlSpot(i.toDouble(), samples[i].glucoseMgdl.toDouble()));
    }

    final values = samples.map((e) => e.glucoseMgdl.toDouble()).toList();
    if (dayTarget != null) values.add(dayTarget!.toDouble());
    final minY = (values.reduce(math.min) - 20).clamp(40, 400).toDouble();
    final maxY = (values.reduce(math.max) + 20).clamp(80, 500).toDouble();


    return SectionCard(
      title: 'Glicose',
      icon: Icons.show_chart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dayTarget != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Linha guia: meta dia $dayTarget mg/dL',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                minX: 0,
                maxX: math.max(0, samples.length - 1).toDouble(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: colors.grid,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: colors.outline),
                    bottom: BorderSide(color: colors.outline),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: chartXInterval(samples.length),
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= samples.length) {
                          return const SizedBox.shrink();
                        }
                        if ((value - i).abs() > 0.01) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            AppTime.formatDateShort(samples[i].recordedAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.muted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: dayTarget == null
                    ? null
                    : ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: dayTarget!.toDouble(),
                            color: colors.muted.withValues(alpha: 0.55),
                            strokeWidth: 1.5,
                            dashArray: [6, 4],
                          ),
                        ],
                      ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) => touched.map((t) {
                      final i = t.x.round().clamp(0, samples.length - 1);
                      final e = samples[i];
                      final when =
                          AppTime.formatDateTimeShort(e.recordedAt);
                      return LineTooltipItem(
                        '$when\n${e.glucoseMgdl} mg/dL',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.18,
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: samples.length <= 40,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 3.5,
                        color: AppColors.primary,
                        strokeWidth: 1.5,
                        strokeColor: colors.dotStroke,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsulinChart extends StatelessWidget {
  const _InsulinChart({required this.entries});

  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final withDose = entries
        .where(
          (e) => e.recommendedInsulin != null || e.appliedInsulin != null,
        )
        .toList();

    if (withDose.isEmpty) {
      return SectionCard(
        title: 'Insulina',
        icon: Icons.water_drop_outlined,
        child: Text(
          'Nenhuma dose registrada no período.',
          style: TextStyle(color: colors.muted),
        ),
      );
    }

    final maxU = withDose
        .map(
          (e) => math.max(e.recommendedInsulin ?? 0, e.appliedInsulin ?? 0),
        )
        .reduce(math.max);
    final maxY = math.max(4.0, (maxU + 1).ceilToDouble());

    return SectionCard(
      title: 'Insulina',
      icon: Icons.water_drop_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LegendDot(color: AppColors.primary, label: 'Recomendada'),
              SizedBox(width: 16),
              _LegendDot(color: AppColors.accent, label: 'Aplicada'),
            ],
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                groupsSpace: withDose.length > 12 ? 4 : 10,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: colors.grid,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: colors.outline),
                    bottom: BorderSide(color: colors.outline),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= withDose.length) {
                          return const SizedBox.shrink();
                        }
                        final step = chartXInterval(withDose.length).round();
                        if (step > 1 && i % step != 0 && i != withDose.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            AppTime.formatDateShort(withDose[i].recordedAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.muted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final e = withDose[groupIndex];
                      final when =
                          AppTime.formatDateTimeShort(e.recordedAt);
                      final label = rodIndex == 0 ? 'Rec.' : 'Apl.';
                      return BarTooltipItem(
                        '$when\n$label ${formatWhole(rod.toY)} U',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: List.generate(withDose.length, (i) {
                  final e = withDose[i];
                  final rec = e.recommendedInsulin;
                  final app = e.appliedInsulin;
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: rec ?? 0,
                        color: rec == null
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.primary,
                        width: withDose.length > 20 ? 4 : 7,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                      BarChartRodData(
                        toY: app ?? 0,
                        color: app == null
                            ? AppColors.accent.withValues(alpha: 0.15)
                            : AppColors.accent,
                        width: withDose.length > 20 ? 4 : 7,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// X-axis label interval for sparse entry charts (exposed for unit tests).
double chartXInterval(int count) {
  if (count <= 6) return 1;
  if (count <= 12) return 2;
  if (count <= 24) return 4;
  return (count / 5).ceilToDouble();
}
