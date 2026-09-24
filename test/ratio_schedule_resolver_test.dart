import 'package:diabetes_app/services/ratio_schedule_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = RatioScheduleResolver();

  test('validate requires midnight and positive values', () {
    expect(
      resolver.validate([
        const RatioSegment(startMinute: 360, value: 40),
      ], label: 'FSI'),
      contains('00:00'),
    );
    expect(
      resolver.validate([
        const RatioSegment(startMinute: 0, value: 0),
      ], label: 'FSI'),
      contains('positivo'),
    );
    expect(
      resolver.validate([
        const RatioSegment(startMinute: 0, value: 40),
      ], label: 'FSI'),
      isNull,
    );
  });

  test('resolve picks active band', () {
    final schedule = resolver.normalize([
      const RatioSegment(startMinute: 0, value: 50),
      const RatioSegment(startMinute: 360, value: 40),
      const RatioSegment(startMinute: 720, value: 35),
    ]);
    expect(resolver.resolve(schedule, 100)?.value, 50);
    expect(resolver.resolve(schedule, 400)?.value, 40);
    expect(resolver.resolve(schedule, 800)?.rangeLabel, '12:00–24:00');
    expect(resolver.mirrorMidnightValue(schedule), 50);
  });

  test('fallback to scalar when empty', () {
    expect(resolver.resolve(const [], 500, fallback: 42)?.value, 42);
  });
}
