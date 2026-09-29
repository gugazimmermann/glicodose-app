import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/hypo_carb_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  AppTime.ensureInitialized();
  AppTime.setLocation(AppTime.defaultLocationName);

  const calc = HypoCarbCalculator();
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

  tz.TZDateTime at(int hour, int minute) =>
      tz.TZDateTime(location, 2026, 9, 16, hour, minute);

  test('55 mg/dL at the day target asks for 11 g', () {
    final plan = calc.calculate(
      glucoseMgdl: 55,
      profile: profile,
      now: at(14, 0),
    );
    expect(plan.ready, isTrue);
    expect(plan.targetMgdl, 110);
    expect(plan.periodLabel, 'dia');
    expect(plan.carbsG, 11);
  });

  test('1 U of IOB raises the same reading to 21 g', () {
    final plan = calc.calculate(
      glucoseMgdl: 55,
      profile: profile,
      iobU: 1,
      now: at(14, 0),
    );
    expect(plan.carbsG, 21);
    expect(plan.iobU, 1);
  });

  test('glucose already at target needs no carbs', () {
    final plan = calc.calculate(
      glucoseMgdl: 110,
      profile: profile,
      now: at(14, 0),
    );
    expect(plan.carbsG, 0);
    expect(plan.portions, isEmpty);
  });

  test('night target changes the grams', () {
    final plan = calc.calculate(
      glucoseMgdl: 55,
      profile: profile,
      now: at(22, 0),
    );
    expect(plan.targetMgdl, 120);
    expect(plan.periodLabel, 'noite');
    // (120-55) * 10 / 50 = 13
    expect(plan.carbsG, 13);
  });

  test('juice and gel portions stay within the gram budget', () {
    final plan = calc.calculate(
      glucoseMgdl: 55,
      profile: profile,
      now: at(14, 0),
    );
    final juice = plan.portions.firstWhere((p) => p.food.contains('laranja'));
    final gel = plan.portions.firstWhere((p) => p.food.contains('gel'));
    expect(juice.quantity, '110 ml');
    expect(juice.carbsG, lessThanOrEqualTo(plan.carbsG));
    expect(gel.quantity, contains('¾'));
    expect(gel.note, 'Não tome o sachê inteiro.');
    expect(gel.carbsG, lessThanOrEqualTo(plan.carbsG));
    final chocolate =
        plan.portions.firstWhere((p) => p.food.contains('chocolate'));
    expect(chocolate.quantity, '18 g');
    expect(chocolate.carbsG, lessThanOrEqualTo(plan.carbsG));
    expect(chocolate.note, contains('devagar'));
    for (final portion in plan.portions) {
      expect(portion.carbsG, lessThanOrEqualTo(plan.carbsG));
    }
  });

  test('AI portions above the budget are replaced by the local table', () {
    final local = HypoCarbCalculator.portionsFor(11);
    final kept = HypoCarbCalculator.acceptPortions(
      carbsG: 11,
      proposed: const [
        HypoCarbPortion(food: 'Suco', quantity: '200 ml', carbsG: 20),
      ],
      fallback: local,
    );
    expect(kept, local);

    final partial = HypoCarbCalculator.acceptPortions(
      carbsG: 11,
      proposed: const [
        HypoCarbPortion(food: 'Suco', quantity: '100 ml', carbsG: 10),
        HypoCarbPortion(food: 'Gel', quantity: '1 sachê', carbsG: 15),
      ],
      fallback: local,
    );
    expect(partial, hasLength(1));
    expect(partial.single.carbsG, 10);
  });

  test('missing factors do not invent a dose', () {
    final plan = calc.calculate(
      glucoseMgdl: 55,
      profile: const Profile(id: 'u'),
      now: at(14, 0),
    );
    expect(plan.ready, isFalse);
    expect(plan.carbsG, 0);
    expect(plan.missingReason, HypoCarbCalculator.missingFactors);
  });
}
