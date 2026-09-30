import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/ratio_schedule_resolver.dart';
import 'package:diabetes_app/services/target_resolver.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:timezone/timezone.dart' as tz;

/// One way to eat the calculated fast carbs. [carbsG] never exceeds the budget.
class HypoCarbPortion {
  const HypoCarbPortion({
    required this.food,
    required this.quantity,
    required this.carbsG,
    this.note,
  });

  final String food;
  final String quantity;
  final int carbsG;
  final String? note;

  factory HypoCarbPortion.fromJson(Map<String, dynamic> json) {
    final carbs = json['carboidratos_g'];
    final parsed = carbs is num ? carbs.round() : int.tryParse('$carbs') ?? 0;
    return HypoCarbPortion(
      food: (json['alimento'] as String?)?.trim() ?? '',
      quantity: (json['quantidade'] as String?)?.trim() ?? '',
      carbsG: parsed < 0 ? 0 : parsed,
    );
  }
}

class HypoCarbPlan {
  const HypoCarbPlan({
    required this.ready,
    required this.carbsG,
    required this.targetMgdl,
    required this.periodLabel,
    required this.iobU,
    required this.portions,
    this.missingReason,
    this.portionsFromAi = false,
  });

  final bool ready;
  final int carbsG;
  final int targetMgdl;
  final String periodLabel;
  final double iobU;
  final List<HypoCarbPortion> portions;
  final String? missingReason;
  final bool portionsFromAi;

  static const reboundWarning = 'Comer além disso pode passar do alvo.';

  HypoCarbPlan copyWith({
    List<HypoCarbPortion>? portions,
    bool? portionsFromAi,
  }) {
    return HypoCarbPlan(
      ready: ready,
      carbsG: carbsG,
      targetMgdl: targetMgdl,
      periodLabel: periodLabel,
      iobU: iobU,
      portions: portions ?? this.portions,
      missingReason: missingReason,
      portionsFromAi: portionsFromAi ?? this.portionsFromAi,
    );
  }
}

/// Inverse of [BolusCalculator]: grams of fast carb to reach the current target.
class HypoCarbCalculator {
  const HypoCarbCalculator({
    this.targetResolver = const TargetResolver(),
    this.ratioResolver = const RatioScheduleResolver(),
  });

  final TargetResolver targetResolver;
  final RatioScheduleResolver ratioResolver;

  static const missingFactors =
      'Perfil incompleto. Cadastre meta, FSI e relação insulina/carboidrato.';

  HypoCarbPlan calculate({
    required int glucoseMgdl,
    required Profile profile,
    double iobU = 0,
    tz.TZDateTime? now,
  }) {
    final effective = targetResolver.resolve(profile, now: now);
    final isfResolved = ratioResolver.resolve(
      profile.isfSchedule,
      effective.minuteOfDay,
      fallback: profile.isfMgdlPerU,
    );
    final icResolved = ratioResolver.resolve(
      profile.icSchedule,
      effective.minuteOfDay,
      fallback: profile.icRatio,
    );
    final isf = isfResolved?.value ?? 0;
    final ic = icResolved?.value ?? 0;
    final hasTargets =
        profile.targetGlucoseMgdl != null && profile.targetNightMgdl != null;
    if (!hasTargets || isf <= 0 || ic <= 0) {
      return HypoCarbPlan(
        ready: false,
        carbsG: 0,
        targetMgdl: hasTargets ? effective.mgdl : 0,
        periodLabel: effective.periodLabel,
        iobU: iobU < 0 ? 0 : iobU,
        portions: const [],
        missingReason: missingFactors,
      );
    }

    final iob = iobU < 0 ? 0.0 : iobU;
    final rise = (effective.mgdl - glucoseMgdl) + iob * isf;
    final carbsG = rise <= 0 ? 0 : asWholeDose(rise * ic / isf);
    return HypoCarbPlan(
      ready: true,
      carbsG: carbsG,
      targetMgdl: effective.mgdl,
      periodLabel: effective.periodLabel,
      iobU: iob,
      portions: portionsFor(carbsG),
    );
  }

  /// How many AI alternatives we keep. Matches the local equivalent list.
  static const maxPortions = 7;

  /// Local TACO-style portions. Each option's carbs stay within [carbsG].
  static List<HypoCarbPortion> portionsFor(int carbsG) {
    if (carbsG <= 0) return const [];
    return [
      _juice(carbsG),
      _soda(carbsG),
      _gel(carbsG),
      _honey(carbsG),
      _sugar(carbsG),
      _chocolate(carbsG),
      _gummy(carbsG),
    ].where((portion) => portion.carbsG > 0).toList();
  }

  /// Alternatives from the model. A portion above [carbsG] is dropped.
  /// If none remain, the local table is kept.
  static List<HypoCarbPortion> acceptPortions({
    required int carbsG,
    required List<HypoCarbPortion> proposed,
    required List<HypoCarbPortion> fallback,
  }) {
    final kept = <HypoCarbPortion>[];
    for (final portion in proposed) {
      if (portion.food.isEmpty || portion.quantity.isEmpty) continue;
      if (portion.carbsG <= 0 || portion.carbsG > carbsG) continue;
      kept.add(portion);
      if (kept.length == maxPortions) break;
    }
    if (kept.isEmpty) return fallback;
    return kept;
  }

  /// 10 g per 100 ml.
  static HypoCarbPortion _juice(int carbsG) {
    return _byDensity(
      carbsG: carbsG,
      food: 'Suco de laranja',
      carbsPer: 10,
      perAmount: 100,
      unit: 'ml',
    );
  }

  /// 10 g per 100 ml. Diet and zero have no carbohydrate.
  static HypoCarbPortion _soda(int carbsG) {
    return _byDensity(
      carbsG: carbsG,
      food: 'Refrigerante comum',
      carbsPer: 10,
      perAmount: 100,
      unit: 'ml',
      note: 'Não use versão diet ou zero.',
    );
  }

  /// 1 g of carbohydrate per 1 g.
  static HypoCarbPortion _sugar(int carbsG) {
    return HypoCarbPortion(
      food: 'Açúcar',
      quantity: '$carbsG g',
      carbsG: carbsG,
    );
  }

  /// About 60 g of carbohydrate per 100 g (milk chocolate). Fat slows absorption.
  static HypoCarbPortion _chocolate(int carbsG) {
    return _byDensity(
      carbsG: carbsG,
      food: 'Barra de chocolate ao leite',
      carbsPer: 60,
      perAmount: 100,
      unit: 'g',
      note: 'Absorve mais devagar por causa da gordura.',
    );
  }

  /// About 80 g of carbohydrate per 100 g.
  static HypoCarbPortion _gummy(int carbsG) {
    return _byDensity(
      carbsG: carbsG,
      food: 'Bala de goma',
      carbsPer: 80,
      perAmount: 100,
      unit: 'g',
    );
  }

  /// Largest whole [unit] whose carbs do not exceed [carbsG].
  static HypoCarbPortion _byDensity({
    required int carbsG,
    required String food,
    required int carbsPer,
    required int perAmount,
    required String unit,
    String? note,
  }) {
    final amount = (carbsG * perAmount) ~/ carbsPer;
    final carbs = (amount * carbsPer) ~/ perAmount;
    return HypoCarbPortion(
      food: food,
      quantity: '$amount $unit',
      carbsG: carbs,
      note: note,
    );
  }

  /// 15 g per sachet. Below 15 g, take only the calculated grams.
  static HypoCarbPortion _gel(int carbsG) {
    const sachet = 15;
    if (carbsG < sachet) {
      return HypoCarbPortion(
        food: 'Sachê de gel de glicose',
        quantity: '$carbsG g (cerca de ${_fraction(carbsG, sachet)} do sachê)',
        carbsG: carbsG,
        note: 'Não tome o sachê inteiro.',
      );
    }
    final whole = carbsG ~/ sachet;
    final rest = carbsG % sachet;
    if (rest == 0) {
      final label = whole == 1 ? '1 sachê (15 g)' : '$whole sachês (15 g cada)';
      return HypoCarbPortion(
        food: 'Sachê de gel de glicose',
        quantity: label,
        carbsG: carbsG,
      );
    }
    final sachetWord = whole == 1 ? '1 sachê' : '$whole sachês';
    return HypoCarbPortion(
      food: 'Sachê de gel de glicose',
      quantity: '$sachetWord e mais $rest g de outro',
      carbsG: carbsG,
      note: 'Não termine o segundo sachê.',
    );
  }

  /// 15 g of carbohydrate in 1 tablespoon (20 g of honey).
  static HypoCarbPortion _honey(int carbsG) {
    const spoonCarbs = 15;
    const spoonMass = 20;
    final spoons = carbsG ~/ spoonCarbs;
    final restCarbs = carbsG % spoonCarbs;
    final restMass = (restCarbs * spoonMass) ~/ spoonCarbs;
    final restPortionCarbs = (restMass * spoonCarbs) ~/ spoonMass;
    final totalCarbs = spoons * spoonCarbs + restPortionCarbs;

    if (spoons == 0) {
      return HypoCarbPortion(
        food: 'Mel',
        quantity: '$restMass g (menos de 1 colher de sopa)',
        carbsG: totalCarbs,
      );
    }
    if (restMass == 0) {
      final label = spoons == 1
          ? '1 colher de sopa'
          : '$spoons colheres de sopa';
      return HypoCarbPortion(food: 'Mel', quantity: label, carbsG: totalCarbs);
    }
    final spoonLabel = spoons == 1
        ? '1 colher de sopa'
        : '$spoons colheres de sopa';
    return HypoCarbPortion(
      food: 'Mel',
      quantity: '$spoonLabel e mais $restMass g',
      carbsG: totalCarbs,
    );
  }

  static String _fraction(int part, int whole) {
    final quarters = ((part / whole) * 4).round().clamp(1, 3);
    switch (quarters) {
      case 1:
        return '¼';
      case 2:
        return '½';
      default:
        return '¾';
    }
  }
}
