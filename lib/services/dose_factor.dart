import 'package:diabetes_app/models/entry.dart';

/// Simple clinical multipliers the user can apply before calculating a dose.
enum DoseSituation {
  none,
  exercise,
  illness,
  alcohol,
}

extension DoseSituationX on DoseSituation {
  String get label {
    switch (this) {
      case DoseSituation.none:
        return 'Nenhum';
      case DoseSituation.exercise:
        return 'Exercício';
      case DoseSituation.illness:
        return 'Doença';
      case DoseSituation.alcohol:
        return 'Álcool';
    }
  }

  String get hint {
    switch (this) {
      case DoseSituation.none:
        return 'Sem ajuste extra';
      case DoseSituation.exercise:
        return 'Reduz ~20% (sugestão conservadora)';
      case DoseSituation.illness:
        return 'Aumenta ~20% (sugestão conservadora)';
      case DoseSituation.alcohol:
        return 'Reduz ~15% (risco de hipo tardia)';
    }
  }

  /// Multiplier applied to the food bolus only (not correction).
  double get foodBolusMultiplier {
    switch (this) {
      case DoseSituation.none:
        return 1.0;
      case DoseSituation.exercise:
        return 0.8;
      case DoseSituation.illness:
        return 1.2;
      case DoseSituation.alcohol:
        return 0.85;
    }
  }
}

/// Applies a situation multiplier to the food portion of a recommendation.
class DoseFactor {
  const DoseFactor();

  double adjustFoodBolus(double bolusComidaU, DoseSituation situation) {
    final m = situation.foodBolusMultiplier;
    if (m == 1.0) return bolusComidaU;
    final adjusted = bolusComidaU * m;
    return adjusted < 0 ? 0 : adjusted;
  }

  InsulinRecommendation applyToRecommendation(
    InsulinRecommendation rec,
    DoseSituation situation, {
    required double doseStep,
  }) {
    if (situation == DoseSituation.none) return rec;
    final food = adjustFoodBolus(rec.bolusComidaU, situation);
    final doseBruta = rec.correcaoU + food;
    final step = doseStep <= 0 ? 1.0 : doseStep;
    final rawFinal = doseBruta - rec.iobU;
    final rounded = ((rawFinal / step).round() * step);
    final doseFinal = rounded < 0 ? 0.0 : rounded;
    final note = [
      if (rec.observacao != null && rec.observacao!.trim().isNotEmpty)
        rec.observacao!.trim(),
      'Ajuste ${situation.label} (×${situation.foodBolusMultiplier}): '
          'sugestão conservadora — confirme com sua equipe.',
    ].join('\n');
    final raw = Map<String, dynamic>.from(rec.raw ?? {});
    raw['bolus_comida_u'] = food;
    raw['insulina_recomendada_u'] = doseFinal;
    raw['dose_bruta_u'] = doseBruta;
    raw['observacao'] = note;
    raw['situacao'] = situation.name;
    return rec.copyWith(
      bolusComidaU: food,
      insulinaRecomendadaU: doseFinal,
      observacao: note,
      raw: raw,
    );
  }
}
