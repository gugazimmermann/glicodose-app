import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/ratio_schedule_resolver.dart';
import 'package:diabetes_app/services/target_resolver.dart';
import 'package:timezone/timezone.dart' as tz;

/// Second insulin dose for fat and protein (Warsaw FPU). Does not change the
/// immediate carb bolus.
class FpuPlan {
  const FpuPlan({
    required this.fatG,
    required this.proteinG,
    required this.fpu,
    required this.equivalentCarbsG,
    required this.laterInsulinU,
    required this.laterHours,
  });

  final double fatG;
  final double proteinG;
  final double fpu;
  final double equivalentCarbsG;
  final double laterInsulinU;
  final int? laterHours;

  bool get hasLaterDose => laterInsulinU > 0 && laterHours != null;
}

class FpuBolus {
  const FpuBolus({
    this.targetResolver = const TargetResolver(),
    this.ratioResolver = const RatioScheduleResolver(),
  });

  final TargetResolver targetResolver;
  final RatioScheduleResolver ratioResolver;

  static const minFpu = 1.0;

  /// Hours until the second injection. Null below [minFpu].
  static int? hoursForFpu(double fpu) {
    if (fpu < minFpu) return null;
    if (fpu < 2) return 3;
    if (fpu < 3) return 4;
    if (fpu < 4) return 5;
    return 8;
  }

  FpuPlan calculate({
    required double fatG,
    required double proteinG,
    required Profile profile,
    tz.TZDateTime? now,
  }) {
    final fat = fatG < 0 ? 0.0 : fatG;
    final protein = proteinG < 0 ? 0.0 : proteinG;
    final kcal = fat * 9 + protein * 4;
    final fpu = kcal / 100;
    final equivalent = fpu * 10;
    final hours = hoursForFpu(fpu);
    if (hours == null) {
      return FpuPlan(
        fatG: fat,
        proteinG: protein,
        fpu: fpu,
        equivalentCarbsG: equivalent,
        laterInsulinU: 0,
        laterHours: null,
      );
    }

    final later = now == null
        ? null
        : tz.TZDateTime.from(now.add(Duration(hours: hours)), now.location);
    final effective = targetResolver.resolve(profile, now: later);
    final icResolved = ratioResolver.resolve(
      profile.icSchedule,
      effective.minuteOfDay,
      fallback: profile.icRatio,
    );
    final ic = icResolved?.value ?? profile.icRatio ?? 0;
    final step = profile.doseStep <= 0 ? 1.0 : profile.doseStep;
    final units = ic <= 0 ? 0.0 : _roundToStep(equivalent / ic, step);

    return FpuPlan(
      fatG: fat,
      proteinG: protein,
      fpu: fpu,
      equivalentCarbsG: equivalent,
      laterInsulinU: units,
      laterHours: units > 0 ? hours : null,
    );
  }

  /// Writes the plan onto [recommendation]. A missing macro stays null.
  InsulinRecommendation apply({
    required InsulinRecommendation recommendation,
    required Profile profile,
    double? fatG,
    double? proteinG,
    tz.TZDateTime? now,
  }) {
    if (fatG == null && proteinG == null) return recommendation;
    final plan = calculate(
      fatG: fatG ?? 0,
      proteinG: proteinG ?? 0,
      profile: profile,
      now: now,
    );
    final attached = attach(recommendation, plan);
    if (fatG != null && proteinG != null) return attached;
    final raw = Map<String, dynamic>.from(attached.raw ?? {});
    if (fatG == null) raw['gordura_g'] = null;
    if (proteinG == null) raw['proteina_g'] = null;
    return attached.copyWith(raw: raw);
  }

  InsulinRecommendation attach(
    InsulinRecommendation recommendation,
    FpuPlan plan,
  ) {
    final raw = Map<String, dynamic>.from(recommendation.raw ?? {});
    raw['gordura_g'] = plan.fatG;
    raw['proteina_g'] = plan.proteinG;
    raw['fpu'] = plan.fpu;
    raw['fpu_equivalente_g'] = plan.equivalentCarbsG;
    raw['fpu_u'] = plan.laterInsulinU;
    raw['fpu_horas'] = plan.laterHours;
    return recommendation.copyWith(raw: raw);
  }

  double _roundToStep(double value, double step) {
    if (value.isNaN || value.isInfinite) return 0;
    if (step <= 0) return value < 0 ? 0 : value;
    final snapped = (value / step).round() * step;
    final cleaned = (snapped * 1000).round() / 1000;
    return cleaned < 0 ? 0 : cleaned;
  }
}
