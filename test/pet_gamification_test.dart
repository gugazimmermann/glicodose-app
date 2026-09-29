import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/services/pet_gamification.dart';

void main() {
  const engine = PetGamification();

  List<PetGlucosePoint> every(
    DateTime start,
    DateTime end, {
    int mgdl = 110,
    int stepMinutes = 15,
  }) {
    final points = <PetGlucosePoint>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      points.add(PetGlucosePoint(at: cursor, glucoseMgdl: mgdl));
      cursor = cursor.add(Duration(minutes: stepMinutes));
    }
    return points;
  }

  Set<String> ids(PetComputation result) =>
      result.unlocked.map((item) => item.id).toSet();

  group('fuel', () {
    test('each full in-range hour is one drop and a low adds none', () {
      final now = DateTime(2026, 9, 28, 17, 10);
      final result = engine.compute(
        glucose: [
          ...every(DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 14)),
          ...every(
            DateTime(2026, 9, 28, 15),
            DateTime(2026, 9, 28, 17),
            mgdl: 55,
          ),
        ],
        logs: const [],
        now: now,
        stored: PetStoredState(),
      );

      expect(result.dropsToday, 6);
      expect(result.mood, PetMood.waiting);
      expect(ids(result), isNot(contains('straight_12')));
    });

    test('12 straight hours unlocks the monarch and fills the day bar', () {
      final now = DateTime(2026, 9, 28, 20);
      final result = engine.compute(
        glucose: every(DateTime(2026, 9, 28, 8), now),
        logs: const [],
        now: now,
        stored: PetStoredState(),
      );

      expect(result.dropsToday, greaterThanOrEqualTo(12));
      expect(result.mood, PetMood.celebrating);
      expect(ids(result), contains('straight_12'));
      expect(ids(result), contains('straight_4'));
      expect(ids(result), contains('afternoon_calm'));
    });

    test('stale reading sleeps without clearing saved drops', () {
      final result = engine.compute(
        glucose: [
          PetGlucosePoint(
            at: DateTime(2026, 9, 28, 8),
            glucoseMgdl: 120,
          ),
        ],
        logs: const [],
        now: DateTime(2026, 9, 28, 12),
        stored: PetStoredState(
          lifetimeDrops: 8,
          unlockedIds: {'glasses'},
          fuelDay: DateTime(2026, 9, 27),
        ),
      );

      expect(result.mood, PetMood.sleeping);
      expect(result.lifetimeDrops, 8);
      expect(ids(result), contains('glasses'));
    });

    test('lifetime drops never shrink when today is recounted lower', () {
      final result = engine.compute(
        glucose: every(DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 10)),
        logs: const [],
        now: DateTime(2026, 9, 28, 10),
        stored: PetStoredState(
          lifetimeDrops: 10,
          dropsSavedToday: 4,
          fuelDay: DateTime(2026, 9, 28),
        ),
      );

      expect(result.dropsToday, 2);
      expect(result.lifetimeDrops, 10);
    });
  });

  group('achievements', () {
    test('hypo treatment is the carb log, not the low', () {
      final low = DateTime(2026, 9, 28, 9);
      final treated = engine.compute(
        glucose: [PetGlucosePoint(at: low, glucoseMgdl: 60)],
        logs: [
          PetCareLog(at: low.add(const Duration(minutes: 10)), carbsG: 15),
        ],
        now: low.add(const Duration(minutes: 15)),
        stored: PetStoredState(),
      );
      final untreated = engine.compute(
        glucose: [PetGlucosePoint(at: low, glucoseMgdl: 60)],
        logs: const [],
        now: low.add(const Duration(minutes: 15)),
        stored: PetStoredState(),
      );

      expect(ids(treated), contains('hypo_care'));
      expect(ids(untreated), isNot(contains('hypo_care')));
      expect(treated.dropsToday, 0);
    });

    test('breakfast, two meals, and a logged dose each have a mark', () {
      final now = DateTime(2026, 9, 28, 20);
      final result = engine.compute(
        glucose: const [],
        logs: [
          PetCareLog(
            at: DateTime(2026, 9, 28, 8),
            appliedInsulinU: 4,
            carbsG: 40,
          ),
          PetCareLog(at: DateTime(2026, 9, 28, 13), carbsG: 50),
        ],
        now: now,
        stored: PetStoredState(),
      );

      expect(ids(result), containsAll([
        'first_log',
        'breakfast_ritual',
        'two_meals',
        'plate_and_pen',
      ]));
    });

    test('return from a high earns a badge and a low does not', () {
      final result = engine.compute(
        glucose: [
          PetGlucosePoint(at: DateTime(2026, 9, 28, 10), glucoseMgdl: 220),
          PetGlucosePoint(at: DateTime(2026, 9, 28, 11), glucoseMgdl: 140),
          PetGlucosePoint(at: DateTime(2026, 9, 28, 12), glucoseMgdl: 60),
          PetGlucosePoint(at: DateTime(2026, 9, 28, 12, 20), glucoseMgdl: 100),
        ],
        logs: const [],
        now: DateTime(2026, 9, 28, 13),
        stored: PetStoredState(),
      );

      expect(ids(result), contains('return_high'));
    });

    test('a rough day pauses the care streak instead of wiping it', () {
      final points = <PetGlucosePoint>[
        ...every(DateTime(2026, 9, 24, 8), DateTime(2026, 9, 24, 16)),
        ...every(DateTime(2026, 9, 25, 8), DateTime(2026, 9, 25, 16)),
        ...every(
          DateTime(2026, 9, 26, 8),
          DateTime(2026, 9, 26, 16),
          mgdl: 230,
        ),
        ...every(DateTime(2026, 9, 27, 8), DateTime(2026, 9, 27, 16)),
      ];
      final result = engine.compute(
        glucose: points,
        logs: const [],
        now: DateTime(2026, 9, 28, 9),
        stored: PetStoredState(),
      );

      expect(result.careStreakDays, 3);
      expect(result.streakPaused, isFalse);
      expect(ids(result), contains('care_pause'));
    });

    test('night window fully in range unlocks the night guardian', () {
      final points = every(
        DateTime(2026, 9, 27, 20),
        DateTime(2026, 9, 28, 6),
      );
      final result = engine.compute(
        glucose: points,
        logs: const [],
        now: DateTime(2026, 9, 28, 10),
        stored: PetStoredState(),
        nightStartMinute: 20 * 60,
        nightEndMinute: 6 * 60,
      );

      expect(ids(result), contains('night_guardian'));
      expect(ids(result), contains('dawn_watch'));
    });
  });
}
