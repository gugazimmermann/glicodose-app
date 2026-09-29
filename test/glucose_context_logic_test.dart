import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/services/glucose_context_logic.dart';
import 'package:diabetes_app/services/history_stats.dart';

void main() {
  const logic = GlucoseContextLogic();

  GlucoseSample sample(int year, int month, int day, int hour, int mgdl) {
    return GlucoseSample(
      glucoseMgdl: mgdl,
      recordedAt: DateTime.utc(year, month, day, hour, 30),
    );
  }

  List<GlucoseSample> tuesdayDrops({
    required List<int> days,
    required int fromHour,
    required int toHour,
    required int fromMgdl,
    required int toMgdl,
    int month = 9,
  }) {
    return [
      for (final day in days) ...[
        sample(2026, month, day, fromHour, fromMgdl),
        sample(2026, month, day, toHour, toMgdl),
      ],
    ];
  }

  group('GlucoseContextLogic detect', () {
    test('bins the hour median and finds a Tuesday 15h drop', () {
      final patterns = logic.detect(
        timezone: 'UTC',
        now: DateTime.utc(2026, 9, 23, 12),
        samples: [
          ...tuesdayDrops(
            days: [1, 8, 15, 22],
            fromHour: 14,
            toHour: 15,
            fromMgdl: 120,
            toMgdl: 60,
          ),
          // Two samples in the same hour: median of 50 and 70 is 60.
          sample(2026, 9, 22, 15, 50),
          sample(2026, 9, 22, 15, 70),
        ],
      );

      expect(patterns, hasLength(1));
      final pattern = patterns.single;
      expect(pattern.weekday, DateTime.tuesday);
      expect(pattern.hour, 15);
      expect(pattern.medianMgdl, 60);
      expect(pattern.medianDropMgdl, 60);
      expect(pattern.occurrences, 4);
      expect(pattern.suggestCarbsG, 15);
      expect(
        GlucoseContextLogic.alertBody(pattern),
        'Historicamente, nas terças-feiras às 15h, sua glicemia cai. '
        'Que tal um lanche de 15g de carboidratos agora?',
      );
      expect(pattern.summaryLabel, 'terça, 15h, queda de cerca de 60 mg/dL');
    });

    test('ignores a drop under 25 mg/dL', () {
      final patterns = logic.detect(
        timezone: 'UTC',
        now: DateTime.utc(2026, 9, 23, 12),
        samples: tuesdayDrops(
          days: [1, 8, 15, 22],
          fromHour: 14,
          toHour: 15,
          fromMgdl: 100,
          toMgdl: 76,
        ),
      );
      expect(patterns, isEmpty);
    });

    test('needs at least 3 dates', () {
      final patterns = logic.detect(
        timezone: 'UTC',
        now: DateTime.utc(2026, 9, 23, 12),
        samples: tuesdayDrops(
          days: [15, 22],
          fromHour: 14,
          toHour: 15,
          fromMgdl: 130,
          toMgdl: 60,
        ),
      );
      expect(patterns, isEmpty);
    });

    test('keeps a 60 percent pattern and skips the snack above hypo', () {
      expect(
        GlucoseContextLogic.meetsPatternThreshold(
          dropDates: 3,
          evaluatedDates: 5,
        ),
        isTrue,
      );
      expect(
        GlucoseContextLogic.meetsPatternThreshold(
          dropDates: 3,
          evaluatedDates: 6,
        ),
        isFalse,
      );

      final patterns = logic.detect(
        timezone: 'UTC',
        now: DateTime.utc(2026, 9, 29, 17),
        samples: [
          ...tuesdayDrops(
            days: [1, 8, 15],
            fromHour: 17,
            toHour: 18,
            fromMgdl: 140,
            toMgdl: 90,
          ),
          ...tuesdayDrops(
            days: [22, 29],
            fromHour: 17,
            toHour: 18,
            fromMgdl: 100,
            toMgdl: 95,
          ),
        ],
      );

      expect(patterns, hasLength(1));
      expect(patterns.single.occurrences, 3);
      expect(patterns.single.dropRate, closeTo(0.6, 0.001));
      expect(patterns.single.suggestCarbsG, isNull);
      expect(
        GlucoseContextLogic.alertBody(patterns.single),
        'Historicamente, nas terças-feiras às 18h, sua glicemia cai.',
      );
    });

    test('uses the profile timezone for the hour bucket', () {
      final patterns = logic.detect(
        timezone: 'America/Sao_Paulo',
        now: DateTime.utc(2026, 9, 23, 12),
        samples: tuesdayDrops(
          days: [1, 8, 15, 22],
          fromHour: 17,
          toHour: 18,
          fromMgdl: 140,
          toMgdl: 60,
        ),
      );
      expect(patterns.single.hour, 15);
      expect(patterns.single.weekday, DateTime.tuesday);
    });
  });

  group('GlucoseContextLogic window and guards', () {
    const pattern = GlucoseContextPattern(
      weekday: DateTime.tuesday,
      hour: 15,
      medianMgdl: 60,
      medianDropMgdl: 40,
      occurrences: 4,
      dropRate: 1,
      suggestCarbsG: 15,
    );

    GlucoseContextAlert? alert({
      int hour = 14,
      int minute = 40,
      int current = 110,
      int? trend,
      bool recentMeal = false,
      String? notifiedOn,
      int weekday = DateTime.tuesday,
      int day = 22,
      List<GlucoseContextPattern>? patterns,
    }) {
      return logic.evaluateAlert(
        patterns: patterns ?? const [pattern],
        now: GlucoseContextClock(
          weekday: weekday,
          hour: hour,
          minute: minute,
          year: 2026,
          month: 9,
          day: day,
        ),
        currentMgdl: current,
        trend: trend,
        recentMeal: recentMeal,
        lastNotifiedOn: {
          '${pattern.weekday}|${pattern.hour}': ?notifiedOn,
        },
      );
    }

    test('opens 20 minutes before the hour and closes at the hour', () {
      expect(
        GlucoseContextLogic.isInLeadWindow(
          nowWeekday: DateTime.tuesday,
          nowHour: 14,
          nowMinute: 39,
          patternWeekday: DateTime.tuesday,
          patternHour: 15,
        ),
        isFalse,
      );
      expect(alert(minute: 40), isNotNull);
      expect(alert(minute: 59), isNotNull);
      expect(alert(hour: 15, minute: 0), isNull);
    });

    test('midnight pattern uses the previous evening', () {
      const midnight = GlucoseContextPattern(
        weekday: DateTime.tuesday,
        hour: 0,
        medianMgdl: 60,
        medianDropMgdl: 40,
        occurrences: 3,
        dropRate: 1,
        suggestCarbsG: 15,
      );
      final hit = logic.evaluateAlert(
        patterns: const [midnight],
        now: const GlucoseContextClock(
          weekday: DateTime.monday,
          hour: 23,
          minute: 40,
          year: 2026,
          month: 9,
          day: 21,
        ),
        currentMgdl: 110,
        recentMeal: false,
        lastNotifiedOn: const {},
      );
      expect(hit?.slotDate, '2026-09-22');
      expect(
        logic.evaluateAlert(
          patterns: const [midnight],
          now: const GlucoseContextClock(
            weekday: DateTime.monday,
            hour: 23,
            minute: 39,
            year: 2026,
            month: 9,
            day: 21,
          ),
          currentMgdl: 110,
          recentMeal: false,
          lastNotifiedOn: const {},
        ),
        isNull,
      );
    });

    test('blocks a recent meal, a repeat the same day, and unsafe glucose', () {
      expect(alert(recentMeal: true), isNull);
      expect(alert(notifiedOn: '2026-09-22'), isNull);
      expect(alert(notifiedOn: '2026-09-15'), isNotNull);
      expect(alert(current: 70), isNull);
      expect(alert(current: 180), isNull);
      expect(alert(trend: GlucoseContextLogic.strongRiseTrend), isNull);
      expect(alert(trend: 4)?.title, GlucoseContextLogic.alertTitle);
    });
  });
}
