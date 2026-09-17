import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/brazil_time.dart';
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

  DateTime? since({DateTime? now}) {
    final n = now ?? DateTime.now();
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

class HistoryStats {
  const HistoryStats({
    required this.count,
    required this.avgGlucose,
    required this.minGlucose,
    required this.maxGlucose,
    required this.inTargetPercent,
    required this.inTargetCount,
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
  final double? inTargetPercent;
  final int inTargetCount;
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

  static HistoryStats fromEntries(
    List<Entry> entries, {
    Profile? profile,
    TargetResolver resolver = const TargetResolver(),
  }) {
    if (entries.isEmpty) {
      return HistoryStats(
        count: 0,
        avgGlucose: null,
        minGlucose: null,
        maxGlucose: null,
        inTargetPercent: null,
        inTargetCount: 0,
        totalAppliedU: 0,
        avgAppliedU: null,
        appliedCount: 0,
        totalRecommendedU: 0,
        recommendedCount: 0,
        avgDoseDeltaU: null,
        doseDeltaCount: 0,
        avgCarbsG: null,
        carbsCount: 0,
        dayTargetMgdl: profile?.targetGlucoseMgdl,
      );
    }

    var glucoseSum = 0;
    var minG = entries.first.glucoseMgdl;
    var maxG = entries.first.glucoseMgdl;
    var inTarget = 0;

    var appliedSum = 0.0;
    var appliedN = 0;
    var recommendedSum = 0.0;
    var recommendedN = 0;
    var deltaSum = 0.0;
    var deltaN = 0;
    var carbsSum = 0.0;
    var carbsN = 0;

    BrazilTime.ensureInitialized();
    final location = BrazilTime.location;

    for (final e in entries) {
      final g = e.glucoseMgdl;
      glucoseSum += g;
      if (g < minG) minG = g;
      if (g > maxG) maxG = g;

      if (profile != null) {
        final br = tz.TZDateTime.from(e.recordedAt.toUtc(), location);
        final target = resolver.resolve(profile, nowBr: br);
        final lo = target.mgdl * (1 - targetTolerance);
        final hi = target.mgdl * (1 + targetTolerance);
        if (g >= lo && g <= hi) inTarget++;
      }

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

    final n = entries.length;
    return HistoryStats(
      count: n,
      avgGlucose: glucoseSum / n,
      minGlucose: minG,
      maxGlucose: maxG,
      inTargetPercent: profile == null ? null : (inTarget / n) * 100,
      inTargetCount: inTarget,
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
}
