import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/bolus_calculator.dart';
import 'package:diabetes_app/services/fpu_bolus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  AppTime.ensureInitialized();
  AppTime.setLocation(AppTime.defaultLocationName);

  const fpu = FpuBolus();
  final location = AppTime.location;
  final profile = Profile(
    id: 'u1',
    targetGlucoseMgdl: 110,
    targetNightMgdl: 120,
    isfMgdlPerU: 50,
    icRatio: 10,
    rapidInsulinName: 'Humalog',
    doseStep: 1,
  );

  tz.TZDateTime at(int hour) => tz.TZDateTime(location, 2026, 9, 16, hour);

  test('40 g fat and 25 g protein ask for 5 U in 8 h', () {
    final plan = fpu.calculate(
      fatG: 40,
      proteinG: 25,
      profile: profile,
      now: at(14),
    );
    // (40*9 + 25*4) / 100 = 4.6 FPU → 46 g → 4.6 U → 5 U, 8 h
    expect(plan.fpu, closeTo(4.6, 0.001));
    expect(plan.equivalentCarbsG, closeTo(46, 0.001));
    expect(plan.laterInsulinU, 5);
    expect(plan.laterHours, 8);
  });

  test('less than 1 FPU has no second dose', () {
    final plan = fpu.calculate(
      fatG: 4,
      proteinG: 1,
      profile: profile,
      now: at(14),
    );
    expect(plan.fpu, lessThan(1));
    expect(plan.laterInsulinU, 0);
    expect(plan.laterHours, isNull);
    expect(plan.hasLaterDose, isFalse);
  });

  test('fat does not change the immediate carb dose', () {
    const bolus = BolusCalculator();
    final nowDose = bolus.calculate(
      glucoseMgdl: 110,
      carboidratosG: 40,
      profile: profile,
      now: at(14),
    );
    final later = fpu.calculate(
      fatG: 40,
      proteinG: 25,
      profile: profile,
      now: at(14),
    );
    expect(nowDose.insulinaRecomendadaU, 4);
    expect(nowDose.bolusComidaU, 4);
    expect(later.laterInsulinU, 5);
  });

  test('delay follows the FPU bands', () {
    expect(FpuBolus.hoursForFpu(0.99), isNull);
    expect(FpuBolus.hoursForFpu(1), 3);
    expect(FpuBolus.hoursForFpu(1.99), 3);
    expect(FpuBolus.hoursForFpu(2), 4);
    expect(FpuBolus.hoursForFpu(3), 5);
    expect(FpuBolus.hoursForFpu(3.99), 5);
    expect(FpuBolus.hoursForFpu(4), 8);
  });

  test('fat and protein in the recommendation feed the plan', () {
    final parsed = InsulinRecommendation.fromJson({
      'carboidratos_g': 40,
      'correcao_u': 0,
      'bolus_comida_u': 4,
      'insulina_recomendada_u': 4,
      'gordura_g': 40,
      'proteina_g': 25,
    });
    expect(parsed.gorduraG, 40);
    expect(parsed.proteinaG, 25);
    final plan = fpu.calculate(
      fatG: parsed.gorduraG!,
      proteinG: parsed.proteinaG!,
      profile: profile,
      now: at(14),
    );
    expect(plan.laterInsulinU, 5);
    expect(plan.laterHours, 8);

    final missing = InsulinRecommendation.fromJson({
      'carboidratos_g': 10,
      'correcao_u': 0,
      'bolus_comida_u': 1,
      'insulina_recomendada_u': 1,
    });
    expect(missing.gorduraG, isNull);
    expect(missing.proteinaG, isNull);
    expect(missing.fpuLaterU, isNull);
    expect(missing.fpuLaterHours, isNull);
  });
}
