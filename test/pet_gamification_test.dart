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
          PetGlucosePoint(at: DateTime(2026, 9, 28, 8), glucoseMgdl: 120),
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

    test('hours since the last save are banked, including a missed day', () {
      final now = DateTime(2026, 9, 28, 10);
      final result = engine.compute(
        glucose: [
          ...every(DateTime(2026, 9, 27, 8), DateTime(2026, 9, 27, 16)),
          ...every(DateTime(2026, 9, 28, 8), now),
        ],
        logs: const [],
        now: now,
        stored: PetStoredState(
          lifetimeDrops: 4,
          dropsSavedToday: 4,
          fuelDay: DateTime(2026, 9, 26),
        ),
      );

      expect(result.dropsToday, 2);
      expect(result.lifetimeDrops, 14);
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

    test('a wide sensor-gap does not count as time in range', () {
      final result = engine.compute(
        glucose: [
          PetGlucosePoint(at: DateTime(2026, 9, 28, 8), glucoseMgdl: 110),
          PetGlucosePoint(at: DateTime(2026, 9, 28, 10), glucoseMgdl: 110),
        ],
        logs: const [],
        now: DateTime(2026, 9, 28, 10, 5),
        stored: PetStoredState(),
        staleMinutes: 120,
      );

      expect(result.dropsToday, 0);
      expect(result.mood, PetMood.curious);
    });

    test('hours after the loaded day stay out of the saved lifetime', () {
      final result = engine.compute(
        glucose: [
          ...every(DateTime(2026, 9, 26, 8), DateTime(2026, 9, 26, 12)),
          ...every(DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 12)),
        ],
        logs: const [],
        now: DateTime(2026, 9, 28, 12),
        stored: PetStoredState(fuelDay: DateTime(2026, 9, 26)),
        accountThrough: DateTime(2026, 9, 26),
      );

      expect(result.dropsToday, 4);
      expect(result.lifetimeDrops, 4);
      expect(result.accountedDay, DateTime(2026, 9, 26));
      expect(result.streakCursor, DateTime(2026, 9, 26));
      expect(result.careStreakDays, 1);
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

      expect(
        ids(result),
        containsAll([
          'first_log',
          'breakfast_ritual',
          'two_meals',
          'plate_and_pen',
        ]),
      );
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

    test('days without readings do not pause or unlock the care badge', () {
      final points = <PetGlucosePoint>[
        for (var day = 21; day <= 27; day++)
          ...every(DateTime(2026, 9, day, 8), DateTime(2026, 9, day, 16)),
      ];
      final result = engine.compute(
        glucose: points,
        logs: const [],
        now: DateTime(2026, 9, 28, 9),
        stored: const PetStoredState(),
      );

      expect(result.careStreakDays, 7);
      expect(result.streakPaused, isFalse);
      expect(ids(result), isNot(contains('care_pause')));
    });

    test('night window fully in range unlocks the night guardian', () {
      final points = every(DateTime(2026, 9, 27, 20), DateTime(2026, 9, 28, 6));
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

  group('nextGoal', () {
    PetComputation snapshot({
      int dropsToday = 0,
      int lifetimeDrops = 0,
      List<String> unlockedIds = const [],
    }) {
      return PetComputation(
        mood: PetMood.curious,
        playfulLine: 'ok',
        quietLine: 'ok',
        suggestion: null,
        dropsToday: dropsToday,
        hoursInRangeToday: dropsToday.toDouble(),
        lifetimeDrops: lifetimeDrops,
        careStreakDays: 0,
        streakPaused: false,
        streakCursor: null,
        unlocked: [
          for (final id in unlockedIds)
            PetGamification.byId(id) ??
                PetAchievement(
                  id: id,
                  category: PetAchievementCategory.sensor,
                  playfulTitle: id,
                  quietTitle: id,
                  detail: id,
                  hint: id,
                ),
        ],
        newlyUnlocked: const [],
        equippedAccessoryId: null,
        shouldNotify: false,
        accountedDay: DateTime(2026, 9, 28),
        dropsOnAccountedDay: dropsToday,
      );
    }

    test('prefers the next locked accessory with drop progress', () {
      final goal = PetGamification.nextGoal(
        snapshot(lifetimeDrops: 5, dropsToday: 2),
        GamificationMode.pet,
      );

      expect(goal, isNotNull);
      expect(goal!.title, contains('Óculos'));
      expect(goal.progressLabel, '5/8 gotas');
      expect(goal.progress, closeTo(5 / 8, 0.001));
    });

    test('falls back to today bar when wardrobe is complete', () {
      final goal = PetGamification.nextGoal(
        snapshot(lifetimeDrops: 64, dropsToday: 4),
        GamificationMode.quiet,
      );

      expect(goal, isNotNull);
      expect(goal!.title, '12 h no alvo hoje');
      expect(goal.progressLabel, '4/12');
    });

    test('picks a locked achievement when accessory and bar are done', () {
      final wardrobe = [
        'scarf',
        'glasses',
        'cape',
        'hat',
        'bow',
        'headphones',
      ];
      final goal = PetGamification.nextGoal(
        snapshot(
          lifetimeDrops: 64,
          dropsToday: 12,
          unlockedIds: wardrobe,
        ),
        GamificationMode.pet,
      );

      expect(goal, isNotNull);
      expect(goal!.title, 'Primeiros passos na reta');
      expect(goal.hint, contains('4 h'));
      expect(goal.progress, isNull);
    });
  });
}
