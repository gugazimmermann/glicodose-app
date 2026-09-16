import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/target_resolver.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:timezone/timezone.dart' as tz;

class BolusCalculator {
  const BolusCalculator({this.targetResolver = const TargetResolver()});

  final TargetResolver targetResolver;

  InsulinRecommendation calculate({
    required int glucoseMgdl,
    required double carboidratosG,
    required Profile profile,
    double iobU = 0,
    String? observacao,
    String source = 'local',
    tz.TZDateTime? nowBr,
  }) {
    final effective = targetResolver.resolve(profile, nowBr: nowBr);
    final target = effective.mgdl.toDouble();
    final isf = profile.isfMgdlPerU ?? 50;
    final ic = profile.icRatio ?? 10;
    final step = profile.doseStep <= 0 ? 1.0 : profile.doseStep;

    final carbs = asWholeDose(carboidratosG).toDouble();
    final correcao = asWholeDose(
      isf <= 0 ? 0 : _max0((glucoseMgdl - target) / isf),
    ).toDouble();
    final bolusComida = asWholeDose(
      ic <= 0 ? 0 : _max0(carbs / ic),
    ).toDouble();
    final doseBruta = correcao + bolusComida;
    final iob = asWholeDose(iobU).toDouble();
    final doseFinal = asWholeDose(_roundToStep(doseBruta - iob, step)).toDouble();

    var note = observacao ?? '';
    if (iob > 0 && doseFinal == 0) {
      note = note.isEmpty
          ? 'IOB de ${formatWhole(iob)} U cobre a dose bruta; recomendação 0 U.'
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

  double _roundToStep(double value, double step) {
    if (step <= 0) return _max0(value);
    final rounded = (value / step).round() * step;
    return _max0(rounded);
  }
}
