import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/basal_reminder_logic.dart';
import 'package:diabetes_app/services/dose_factor.dart';
import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/export_service.dart';
import 'package:diabetes_app/services/history_stats.dart';
import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/libre_alert_logic.dart';
import 'package:diabetes_app/services/supporter_webhook_mapping.dart';
import 'package:diabetes_app/services/support_service.dart';
import 'package:diabetes_app/services/target_resolver.dart';

void main() {
  setUpAll(() {
    AppTime.ensureInitialized();
    AppTime.setLocation(AppTime.defaultLocationName);
    tz_data.initializeTimeZones();
  });

  group('HistoryStats extras', () {
    test('period labels and since windows', () {
      expect(HistoryPeriod.days7.label, '7 dias');
      expect(HistoryPeriod.days30.label, '30 dias');
      expect(HistoryPeriod.all.label, 'Tudo');
      final now = AppTime.now();
      expect(
        now.difference(HistoryPeriod.days30.since(now: now)!).inDays,
        30,
      );
      expect(HistoryPeriod.all.since(now: now), isNull);
      expect(HistoryPeriod.days7.since(), isNotNull);
    });

    test('in-target and insulin/carbs aggregates with profile', () {
      final profile = Profile(
        id: 'u1',
        targetGlucoseMgdl: 100,
        targetNightMgdl: 120,
        nightStartMinute: 1200,
        nightEndMinute: 359,
        isfMgdlPerU: 50,
        icRatio: 10,
        rapidInsulinName: 'Humalog',
      );
      final entries = [
        Entry(
          id: 'e1',
          userId: 'u1',
          recordedAt: DateTime.utc(2026, 3, 1, 15),
          glucoseMgdl: 100,
          appliedInsulin: 4,
          recommendedInsulin: 5,
          gptRawResponse: const {'carboidratos_g': 40},
        ),
        Entry(
          id: 'e2',
          userId: 'u1',
          recordedAt: DateTime.utc(2026, 3, 1, 16),
          glucoseMgdl: 250,
          appliedInsulin: 2,
          recommendedInsulin: 2,
        ),
      ];
      final stats = HistoryStats.fromEntries(entries, profile: profile);
      expect(stats.inTargetCount, greaterThan(0));
      expect(stats.inTargetPercent, isNotNull);
      expect(stats.appliedCount, 2);
      expect(stats.totalAppliedU, 6);
      expect(stats.avgAppliedU, 3);
      expect(stats.recommendedCount, 2);
      expect(stats.doseDeltaCount, 2);
      expect(stats.avgDoseDeltaU, 0.5);
      expect(stats.carbsCount, 1);
      expect(stats.avgCarbsG, 40);
      expect(stats.dayTargetMgdl, 100);
      expect(HistoryStats.empty.count, 0);
      expect(HistoryStats.estimateGmi(null), isNull);
    });
  });

  group('DoseFactor extras', () {
    test('labels, hints and all situations', () {
      for (final s in DoseSituation.values) {
        expect(s.label, isNotEmpty);
        expect(s.hint, isNotEmpty);
        expect(s.foodBolusMultiplier, greaterThan(0));
      }
      const factor = DoseFactor();
      expect(factor.adjustFoodBolus(10, DoseSituation.none), 10);
      expect(factor.adjustFoodBolus(10, DoseSituation.illness), closeTo(12, 0.01));
      expect(factor.adjustFoodBolus(10, DoseSituation.alcohol), closeTo(8.5, 0.01));

      const rec = InsulinRecommendation(
        carboidratosG: 40,
        correcaoU: 1,
        bolusComidaU: 4,
        insulinaRecomendadaU: 5,
        iobU: 1,
        observacao: 'base',
        raw: {'a': 1},
      );
      final none = factor.applyToRecommendation(
        rec,
        DoseSituation.none,
        doseStep: 1,
      );
      expect(identical(none, rec) || none.insulinaRecomendadaU == 5, isTrue);

      final illness = factor.applyToRecommendation(
        rec,
        DoseSituation.illness,
        doseStep: 0,
      );
      expect(illness.observacao, contains('Doença'));
      expect(illness.insulinaRecomendadaU, greaterThanOrEqualTo(0));
    });
  });

  group('LibreAlertLogic extras', () {
    test('notifies hyper and zone name helpers', () {
      final logic = LibreAlertLogic();
      final now = DateTime(2026, 9, 21, 12);
      final d = logic.evaluateReading(
        reading: LibreGlucoseReading(
          glucoseMgdl: 220,
          recordedAt: now,
          trend: 4,
        ),
        previousZone: LibreAlertZone.ok,
        now: now,
      );
      expect(d.shouldNotify, isTrue);
      expect(d.zone, LibreAlertZone.hyper);
      expect(d.title, contains('alta'));
      expect(d.notificationId, LibreAlertLogic.hyperNotificationId);

      expect(LibreAlertLogic.zoneFromName('hypo'), LibreAlertZone.hypo);
      expect(LibreAlertLogic.zoneFromName('hyper'), LibreAlertZone.hyper);
      expect(LibreAlertLogic.zoneFromName(null), LibreAlertZone.ok);
      expect(LibreAlertLogic.zoneName(LibreAlertZone.hypo), 'hypo');
      expect(LibreAlertLogic.zoneName(LibreAlertZone.hyper), 'hyper');
      expect(LibreAlertLogic.zoneName(LibreAlertZone.ok), 'ok');

      // hypo → hyper jump when clearing above hyper
      expect(
        logic.zoneForGlucose(200, LibreAlertZone.hypo),
        LibreAlertZone.hyper,
      );
      // hyper → hypo jump when clearing below hypo
      expect(
        logic.zoneForGlucose(60, LibreAlertZone.hyper),
        LibreAlertZone.hypo,
      );
    });
  });

  group('BasalReminderLogic extras', () {
    test('defaults and invalid timezone fall back', () {
      final loc = tz.getLocation('America/Sao_Paulo');
      final next = BasalReminderLogic.nextOccurrence(
        minutesFromMidnight: 8 * 60,
        location: loc,
      );
      expect(next.hour, 8);

      final list = BasalReminderLogic.nextOccurrences(
        timesMinutes: [480],
        timezone: 'Not/Valid',
        from: tz.TZDateTime(loc, 2026, 9, 21, 7),
      );
      expect(list, hasLength(1));

      final withNullTz = BasalReminderLogic.nextOccurrences(
        timesMinutes: [480],
        from: tz.TZDateTime(loc, 2026, 9, 21, 7),
      );
      expect(withNullTz, hasLength(1));
    });
  });

  group('TargetResolver extras', () {
    test('displayLabel and resolve without explicit now', () {
      final profile = Profile(
        id: 'u1',
        targetGlucoseMgdl: 110,
        targetNightMgdl: 130,
        nightStartMinute: 1200,
        nightEndMinute: 359,
      );
      const resolver = TargetResolver();
      expect(resolver.isNightWindow(
        minuteOfDay: 10,
        nightStartMinute: 100,
        nightEndMinute: 100,
      ), isFalse);
      final effective = resolver.resolve(profile);
      expect(effective.displayLabel, contains('Meta aplicada'));
      expect(effective.mgdl, anyOf(110, 130));
    });
  });

  group('ExportService text + CSV escape', () {
    test('buildCsv escapes commas/quotes and merges timeline', () {
      const export = ExportService();
      final csv = export.buildCsv(
        [
          Entry(
            id: 'e1',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 12),
            glucoseMgdl: 140,
            foodText: 'arroz, feijão "caseiro"',
            recommendedInsulin: 5,
            appliedInsulin: 4,
            gptRawResponse: const {'carboidratos_g': 45},
          ),
        ],
        basalDoses: [
          BasalDose(
            id: 'b1',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 22),
            units: 18,
            insulinName: 'Lantus, U300',
            notes: 'linha\n2',
          ),
        ],
      );
      expect(csv, contains('bolus,'));
      expect(csv, contains('"arroz, feijão ""caseiro"""'));
      expect(csv, contains('basal,'));
    });

    test('buildTextReport includes profile, stats and timeline', () {
      AppTime.setLocation('America/Sao_Paulo');
      const export = ExportService();
      final profile = Profile(
        id: 'u1',
        fullName: 'Ana',
        targetGlucoseMgdl: 100,
        targetNightMgdl: 110,
        isfMgdlPerU: 50,
        icRatio: 10,
        rapidInsulinName: 'Humalog',
        basalInsulinName: 'Tresiba',
        basalDoseU: 20,
        timezone: 'America/Sao_Paulo',
      );
      final text = export.buildTextReport(
        profile: profile,
        entries: [
          Entry(
            id: 'e1',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 12),
            glucoseMgdl: 140,
            foodText: 'pão',
            recommendedInsulin: 5,
            appliedInsulin: 4,
            gptRawResponse: const {'carboidratos_g': 30},
          ),
          Entry(
            id: 'e2',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 13),
            glucoseMgdl: 90,
            recommendedInsulin: 0,
          ),
        ],
        basalDoses: [
          BasalDose(
            id: 'b1',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 22),
            units: 18,
            insulinName: 'Tresiba',
            notes: 'ok',
          ),
          BasalDose(
            id: 'b2',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 20, 22),
            units: 18,
          ),
        ],
      );
      expect(text, contains('GlicoDose'));
      expect(text, contains('Ana'));
      expect(text, contains('TIR'));
      expect(text, contains('GMI'));
      expect(text, contains('[Bolus]'));
      expect(text, contains('[Basal]'));
      expect(text, contains('orientação médica'));

      final bare = export.buildTextReport(
        profile: null,
        entries: const [],
        basalDoses: const [],
      );
      expect(bare, contains('0 bolus'));
    });
  });

  group('IobCache extras', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fromEntries filters and corrupt load returns null', () async {
      final doses = IobCache.fromEntries([
        Entry(
          id: 'e1',
          userId: 'u1',
          recordedAt: DateTime.utc(2026, 1, 1),
          glucoseMgdl: 100,
          appliedInsulin: 3,
        ),
        Entry(
          id: 'e2',
          userId: 'u1',
          recordedAt: DateTime.utc(2026, 1, 1),
          glucoseMgdl: 100,
          appliedInsulin: 0,
        ),
        Entry(
          id: 'e3',
          userId: 'u1',
          recordedAt: DateTime.utc(2026, 1, 1),
          glucoseMgdl: 100,
        ),
      ]);
      expect(doses, hasLength(1));
      expect(doses.first.toJson()['applied_u'], 3);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(IobCache.prefsKey, '{not-json');
      expect(await IobCache.load(), isNull);

      expect(
        IobCache.compute(doses: const [], durationHours: 4, now: DateTime.now())
            .iobU,
        0,
      );
      expect(
        IobCache.compute(
          doses: doses,
          durationHours: 0,
          now: DateTime.now(),
        ).iobU,
        0,
      );
    });
  });

  group('Support webhook + purchaseErrorMessage', () {
    test('covers remaining status/store mappings', () {
      expect(resolveSupporterStatus('SUBSCRIPTION_EXTENDED'), 'active');
      expect(resolveSupporterStatus('NON_RENEWING_PURCHASE'), 'active');
      expect(resolveSupporterStatus('TEMPORARY_ENTITLEMENT_GRANT'), 'active');
      expect(resolveSupporterStatus('REFUND_REVERSED'), 'active');
      expect(mapStore(null), isNull);
      expect(mapStore('MAC_APP_STORE'), 'apple');
      expect(mapStore('AMAZON'), 'amazon');
      expect(mapStore('PROMOTIONAL'), 'promotional');
    });

    test('purchaseErrorMessage for generic errors', () {
      expect(SupportService.purchaseErrorMessage(Exception('x')), contains('x'));
    });
  });

  group('EntriesPage', () {
    test('pagination getters', () {
      const empty = EntriesPage(
        entries: [],
        total: 0,
        page: 0,
        pageSize: 50,
      );
      expect(empty.totalPages, 1);
      expect(empty.hasPrev, isFalse);
      expect(empty.hasNext, isFalse);

      const mid = EntriesPage(
        entries: [],
        total: 120,
        page: 1,
        pageSize: 50,
      );
      expect(mid.totalPages, 3);
      expect(mid.hasPrev, isTrue);
      expect(mid.hasNext, isTrue);
    });
  });
}
