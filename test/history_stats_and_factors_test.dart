import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/dose_factor.dart';
import 'package:diabetes_app/services/history_stats.dart';

void main() {
  setUpAll(() {
    AppTime.ensureInitialized();
    AppTime.setLocation(AppTime.defaultLocationName);
  });

  group('HistoryStats', () {
    test('computes TIR 70-180 and GMI', () {
      final entries = [
        _entry(100),
        _entry(150),
        _entry(200),
        _entry(60),
      ];
      final stats = HistoryStats.fromEntries(entries);
      expect(stats.count, 4);
      expect(stats.tirCount, 2); // 100 and 150
      expect(stats.tirPercent, closeTo(50, 0.01));
      expect(stats.avgGlucose, closeTo(127.5, 0.01));
      expect(stats.gmiPercent, isNotNull);
      expect(stats.gmiPercent!, closeTo(3.31 + 0.02392 * 127.5, 0.01));
    });

    test('compute uses glicemias over entry glucose for TIR', () {
      final entries = [_entry(250)];
      final samples = [
        GlucoseSample(
          glucoseMgdl: 80,
          recordedAt: DateTime.utc(2026, 3, 1, 10),
        ),
        GlucoseSample(
          glucoseMgdl: 90,
          recordedAt: DateTime.utc(2026, 3, 1, 11),
        ),
      ];
      final stats = HistoryStats.compute(
        entries: entries,
        glucoseSamples: samples,
      );
      expect(stats.count, 2);
      expect(stats.tirCount, 2);
      expect(stats.avgGlucose, 85);
    });

    test('HistoryPeriod.since anchors on AppTime', () {
      final anchor = AppTime.now();
      final since = HistoryPeriod.days7.since(now: anchor);
      expect(since, isNotNull);
      expect(anchor.difference(since!).inDays, 7);
    });
  });

  group('DoseFactor', () {
    test('reduces food bolus for exercise', () {
      const rec = InsulinRecommendation(
        carboidratosG: 50,
        correcaoU: 2,
        bolusComidaU: 5,
        insulinaRecomendadaU: 7,
        iobU: 0,
      );
      final next = const DoseFactor().applyToRecommendation(
        rec,
        DoseSituation.exercise,
        doseStep: 1,
      );
      expect(next.bolusComidaU, closeTo(4.0, 0.01));
      expect(next.insulinaRecomendadaU, 6);
      expect(next.observacao, contains('Exercício'));
    });
  });
}

Entry _entry(int glucose) {
  return Entry(
    id: 'e-$glucose',
    userId: 'u1',
    recordedAt: DateTime.utc(2026, 3, 1, 12),
    glucoseMgdl: glucose,
  );
}
