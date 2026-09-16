import 'package:diabetes_app/services/target_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = TargetResolver();

  test('19:59 is day for 20:00-05:59 window', () {
    expect(
      resolver.isNightWindow(
        minuteOfDay: 19 * 60 + 59,
        nightStartMinute: 1200,
        nightEndMinute: 359,
      ),
      isFalse,
    );
  });

  test('20:00 is night', () {
    expect(
      resolver.isNightWindow(
        minuteOfDay: 20 * 60,
        nightStartMinute: 1200,
        nightEndMinute: 359,
      ),
      isTrue,
    );
  });

  test('05:59 is night', () {
    expect(
      resolver.isNightWindow(
        minuteOfDay: 5 * 60 + 59,
        nightStartMinute: 1200,
        nightEndMinute: 359,
      ),
      isTrue,
    );
  });

  test('06:00 is day', () {
    expect(
      resolver.isNightWindow(
        minuteOfDay: 6 * 60,
        nightStartMinute: 1200,
        nightEndMinute: 359,
      ),
      isFalse,
    );
  });

  test('same-day night window works', () {
    expect(
      resolver.isNightWindow(
        minuteOfDay: 2 * 60,
        nightStartMinute: 60,
        nightEndMinute: 300,
      ),
      isTrue,
    );
    expect(
      resolver.isNightWindow(
        minuteOfDay: 6 * 60,
        nightStartMinute: 60,
        nightEndMinute: 300,
      ),
      isFalse,
    );
  });
}
