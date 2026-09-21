import 'dart:math' as math;

import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/target_resolver.dart';
import 'package:timezone/timezone.dart' as tz;

enum HistoryPeriod { days7, days30, all }

extension HistoryPeriodX on HistoryPeriod {
  String get label {
    switch (this) {
      case HistoryPeriod.days7:
        return '7 dias';
      case HistoryPeriod.days30:
        return '30 dias';
      case HistoryPeriod.all:
        return 'Tudo';
    }
  }

  /// Anchor is profile timezone "now" (not device local).
  DateTime? since({DateTime? now}) {
    final n = now ?? AppTime.now();
    switch (this) {
      case HistoryPeriod.days7:
        return n.subtract(const Duration(days: 7));
      case HistoryPeriod.days30:
        return n.subtract(const Duration(days: 30));
      case HistoryPeriod.all:
        return null;
    }
  }
}

/// Sparse or dense glucose point for charts / TIR / GMI.
class GlucoseSample {
  const GlucoseSample({
    required this.glucoseMgdl,
    required this.recordedAt,
  });

  final int glucoseMgdl;
  final DateTime recordedAt;
}

class HistoryStats {
  const HistoryStats({
    required this.count,
    required this.avgGlucose,
    required this.minGlucose,
    required this.maxGlucose,
    required this.inTargetPercent,
    required this.inTargetCount,
    required this.tirPercent,
    required this.tirCount,
    required this.gmiPercent,
    required this.totalAppliedU,
    required this.avgAppliedU,
    required this.appliedCount,
    required this.totalRecommendedU,
    required this.recommendedCount,
    required this.avgDoseDeltaU,
    required this.doseDeltaCount,
    required this.avgCarbsG,
    required this.carbsCount,
    required this.dayTargetMgdl,
  });

  final int count;
  final double? avgGlucose;
  final int? minGlucose;
  final int? maxGlucose;
  /// Personal target ±20% (legacy / prescrito).
  final double? inTargetPercent;
  final int inTargetCount;
  /// Clinical TIR 70–180 mg/dL.
  final double? tirPercent;
  final int tirCount;
  /// Glucose Management Indicator (estimated A1c %).
  final double? gmiPercent;
  final double totalAppliedU;
  final double? avgAppliedU;
  final int appliedCount;
  final double totalRecommendedU;
  final int recommendedCount;
  /// Mean of (recommended − applied) when both present.
  final double? avgDoseDeltaU;
  final int doseDeltaCount;
  final double? avgCarbsG;
  final int carbsCount;
  final int? dayTargetMgdl;

  static const empty = HistoryStats(
    count: 0,
    avgGlucose: null,
    minGlucose: null,
    maxGlucose: null,
    inTargetPercent: null,
    inTargetCount: 0,
    tirPercent: null,
    tirCount: 0,
    gmiPercent: null,
    totalAppliedU: 0,
    avgAppliedU: null,
    appliedCount: 0,
    totalRecommendedU: 0,
    recommendedCount: 0,
    avgDoseDeltaU: null,
    doseDeltaCount: 0,
    avgCarbsG: null,
    carbsCount: 0,
    dayTargetMgdl: null,
  );

  /// Readings within ±20% of the day/night target for that timestamp.
  static const targetTolerance = 0.20;

  /// Standard clinical time-in-range bounds (mg/dL).
  static const tirLowMgdl = 70;
  static const tirHighMgdl = 180;

  /// GMI ≈ 3.31 + 0.02392 × mean glucose (mg/dL). Requires ≥1 reading.
  static double? estimateGmi(double? avgGlucoseMgdl) {
    if (avgGlucoseMgdl == null) return null;
    return 3.31 + 0.02392 * avgGlucoseMgdl;
  }

  /// Prefer dense [glucoseSamples] for TIR/GMI; insulin/carbs always from [entries].
  static HistoryStats compute({
    required List<Entry> entries,
    List<GlucoseSample> glucoseSamples = const [],
    Profile? profile,
    TargetResolver resolver = const TargetResolver(),
  }) {
    final samples = glucoseSamples.isNotEmpty
        ? glucoseSamples
        : entries
            .map(
              (e) => GlucoseSample(
                glucoseMgdl: e.glucoseMgdl,
                recordedAt: e.recordedAt,
              ),
            )
            .toList();

    AppTime.ensureInitialized();
    final location = AppTime.location;

    int? minG;
    int? maxG;
    var glucoseSum = 0;
    var inTarget = 0;
    var tir = 0;
    for (final s in samples) {
      final g = s.glucoseMgdl;
      glucoseSum += g;
      minG = minG == null ? g : math.min(minG, g);
      maxG = maxG == null ? g : math.max(maxG, g);
      if (g >= tirLowMgdl && g <= tirHighMgdl) tir++;
      if (profile != null) {
        final br = tz.TZDateTime.from(s.recordedAt.toUtc(), location);
        final target = resolver.resolve(profile, now: br);
        final lo = target.mgdl * (1 - targetTolerance);
        final hi = target.mgdl * (1 + targetTolerance);
        if (g >= lo && g <= hi) inTarget++;
      }
    }

    var appliedSum = 0.0;
    var appliedN = 0;
    var recommendedSum = 0.0;
    var recommendedN = 0;
    var deltaSum = 0.0;
    var deltaN = 0;
    var carbsSum = 0.0;
    var carbsN = 0;
    for (final e in entries) {
      final applied = e.appliedInsulin;
      if (applied != null) {
        appliedSum += applied;
        appliedN++;
      }
      final recommended = e.recommendedInsulin;
      if (recommended != null) {
        recommendedSum += recommended;
        recommendedN++;
      }
      if (applied != null && recommended != null) {
        deltaSum += recommended - applied;
        deltaN++;
      }
      final carbs = (e.gptRawResponse?['carboidratos_g'] as num?)?.toDouble();
      if (carbs != null) {
        carbsSum += carbs;
        carbsN++;
      }
    }

    final n = samples.length;
    final avg = n == 0 ? null : glucoseSum / n;
    return HistoryStats(
      count: n,
      avgGlucose: avg,
      minGlucose: minG,
      maxGlucose: maxG,
      inTargetPercent:
          profile == null || n == 0 ? null : (inTarget / n) * 100,
      inTargetCount: inTarget,
      tirPercent: n == 0 ? null : (tir / n) * 100,
      tirCount: tir,
      gmiPercent: estimateGmi(avg),
      totalAppliedU: appliedSum,
      avgAppliedU: appliedN == 0 ? null : appliedSum / appliedN,
      appliedCount: appliedN,
      totalRecommendedU: recommendedSum,
      recommendedCount: recommendedN,
      avgDoseDeltaU: deltaN == 0 ? null : deltaSum / deltaN,
      doseDeltaCount: deltaN,
      avgCarbsG: carbsN == 0 ? null : carbsSum / carbsN,
      carbsCount: carbsN,
      dayTargetMgdl: profile?.targetGlucoseMgdl,
    );
  }

  static HistoryStats fromEntries(
    List<Entry> entries, {
    Profile? profile,
    TargetResolver resolver = const TargetResolver(),
  }) {
    return compute(entries: entries, profile: profile, resolver: resolver);
  }

  /// Downsample dense CGM series for charting (keeps first/last).
  static List<GlucoseSample> downsample(
    List<GlucoseSample> samples, {
    int maxPoints = 500,
  }) {
    if (samples.length <= maxPoints) return samples;
    final step = samples.length / maxPoints;
    final out = <GlucoseSample>[];
    for (var i = 0; i < maxPoints - 1; i++) {
      out.add(samples[(i * step).floor()]);
    }
    out.add(samples.last);
    return out;
  }
}
