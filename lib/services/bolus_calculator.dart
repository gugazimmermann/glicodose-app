import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/ratio_schedule_resolver.dart';
import 'package:diabetes_app/services/target_resolver.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:timezone/timezone.dart' as tz;

class BolusCalculator {
  const BolusCalculator({
    this.targetResolver = const TargetResolver(),
    this.ratioResolver = const RatioScheduleResolver(),
  });

  final TargetResolver targetResolver;
  final RatioScheduleResolver ratioResolver;

  InsulinRecommendation calculate({
    required int glucoseMgdl,
    required double carboidratosG,
    required Profile profile,
    double iobU = 0,
    String? observacao,
    String source = 'local',
    tz.TZDateTime? now,
  }) {
    final effective = targetResolver.resolve(profile, now: now);
    final target = effective.mgdl.toDouble();
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
    final isf = isfResolved?.value ?? profile.isfMgdlPerU ?? 50;
    final ic = icResolved?.value ?? profile.icRatio ?? 10;
    final step = profile.doseStep <= 0 ? 1.0 : profile.doseStep;

    final carbs = _grams(carboidratosG);
    final correcao = _roundToStep(
      isf <= 0 ? 0 : _max0((glucoseMgdl - target) / isf),
      step,
    );
    final bolusComida = _roundToStep(ic <= 0 ? 0 : _max0(carbs / ic), step);
    final doseBruta = correcao + bolusComida;
    final iob = _roundToStep(iobU, step);
    final doseFinal = _roundToStep(doseBruta - iob, step);

    var note = observacao ?? '';
    if (iob > 0 && doseFinal == 0) {
      note = note.isEmpty
          ? 'IOB de ${formatDose(iob)} U cobre a dose bruta; recomendação 0 U.'
          : note;
    }

    final raw = <String, dynamic>{
      'carboidratos_g': carbs,
      'correcao_u': correcao,
      'bolus_comida_u': bolusComida,
      'iob_u': iob,
      'insulina_recomendada_u': doseFinal,
      'observacao': note,
      'source': source,
      'dose_bruta_u': doseBruta,
      'meta_mgdl': effective.mgdl,
      'meta_periodo': effective.periodLabel,
      'horario_br': effective.timeLabel,
      'isf_aplicado': isf,
      'ic_aplicado': ic,
      if (isfResolved != null) 'isf_faixa': isfResolved.rangeLabel,
      if (icResolved != null) 'ic_faixa': icResolved.rangeLabel,
    };

    return InsulinRecommendation(
      carboidratosG: carbs,
      correcaoU: correcao,
      bolusComidaU: bolusComida,
      insulinaRecomendadaU: doseFinal,
      iobU: iob,
      observacao: note,
      source: source,
      metaMgdl: effective.mgdl,
      metaPeriodo: effective.periodLabel,
      horarioBr: effective.timeLabel,
      raw: raw,
    );
  }

  double _max0(double v) => v < 0 ? 0 : v;

  /// Carb grams stay as informed. Only insulin units are rounded.
  double _grams(double value) {
    if (value.isNaN || value.isInfinite || value < 0) return 0;
    return value;
  }

  double _roundToStep(double value, double step) {
    if (value.isNaN || value.isInfinite) return 0;
    if (step <= 0) return _max0(value);
    final snapped = (value / step).round() * step;
    final cleaned = (snapped * 1000).round() / 1000;
    return _max0(cleaned);
  }
}
