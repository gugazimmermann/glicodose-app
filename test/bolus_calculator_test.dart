import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/bolus_calculator.dart';
import 'package:diabetes_app/services/target_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  AppTime.ensureInitialized();
  AppTime.setLocation(AppTime.defaultLocationName);

  const calc = BolusCalculator();
  final location = AppTime.location;

  final profile = Profile(
    id: 'u1',
    diabetesType: Profile.diabetesType1,
    targetGlucoseMgdl: 110,
    targetNightMgdl: 120,
    nightStartMinute: 1200,
    nightEndMinute: 359,
    isfMgdlPerU: 50,
    icRatio: 10,
    rapidInsulinName: 'Humalog',
    doseStep: 1,
  );

  tz.TZDateTime at(int hour, int minute) => tz.TZDateTime(
        location,
        2026,
        9,
        16,
        hour,
        minute,
      );

  test('day target used at 14:00', () {
    final r = calc.calculate(
      glucoseMgdl: 210,
      carboidratosG: 0,
      profile: profile,
      now: at(14, 0),
    );
    // (210-110)/50 = 2
    expect(r.metaMgdl, 110);
    expect(r.metaPeriodo, 'dia');
    expect(r.correcaoU, 2);
    expect(r.insulinaRecomendadaU, 2);
  });

  test('night target used at 22:00 changes correction', () {
    final r = calc.calculate(
      glucoseMgdl: 210,
      carboidratosG: 0,
      profile: profile,
      now: at(22, 0),
    );
    // (210-120)/50 = 1.8 -> 2
    expect(r.metaMgdl, 120);
    expect(r.metaPeriodo, 'noite');
    expect(r.correcaoU, 2);
    expect(r.insulinaRecomendadaU, 2);
  });

  test('food bolus from carbs', () {
    final r = calc.calculate(
      glucoseMgdl: 110,
      carboidratosG: 45,
      profile: profile,
      now: at(12, 0),
    );
    // 45/10 = 4.5 -> 5
    expect(r.correcaoU, 0);
    expect(r.bolusComidaU, 5);
    expect(r.insulinaRecomendadaU, 5);
  });

  test('subtracts IOB and never goes negative', () {
    final r = calc.calculate(
      glucoseMgdl: 210,
      carboidratosG: 20,
      profile: profile,
      iobU: 10,
      now: at(12, 0),
    );
    // correcao 2 + comida 2 = 4 - 10 => 0
    expect(r.insulinaRecomendadaU, 0);
  });

  test('prescription example I:C 25 FSI 150', () {
    final p = profile.copyWith(isfMgdlPerU: 150, icRatio: 25);
    final r = calc.calculate(
      glucoseMgdl: 260,
      carboidratosG: 50,
      profile: p,
      now: at(12, 0),
    );
    // correcao (260-110)/150 = 1; comida 50/25 = 2; total 3
    expect(r.correcaoU, 1);
    expect(r.bolusComidaU, 2);
    expect(r.insulinaRecomendadaU, 3);
  });

  test('same UTC instant can flip day/night when timezone changes', () {
    const resolver = TargetResolver();
    // 2026-09-16 23:00 UTC = 20:00 Sao Paulo (night) and 19:00 New York (day
    // if night starts at 20:00).
    final utc = DateTime.utc(2026, 9, 16, 23, 0);

    AppTime.setLocation('America/Sao_Paulo');
    final sp = resolver.resolve(
      profile,
      now: AppTime.fromUtc(utc),
    );
    expect(sp.isNight, isTrue);
    expect(sp.mgdl, 120);

    AppTime.setLocation('America/New_York');
    final ny = resolver.resolve(
      profile,
      now: AppTime.fromUtc(utc),
    );
    expect(ny.isNight, isFalse);
    expect(ny.mgdl, 110);

    AppTime.setLocation(AppTime.defaultLocationName);
  });
}
