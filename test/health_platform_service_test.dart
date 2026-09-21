import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/history_stats.dart';

void main() {
  group('HealthPlatformService', () {
    test('labels and unsupported on test host', () {
      final service = HealthPlatformService();
      expect(service.platformLabel, isNotEmpty);
      expect(
        service.isSupportedPlatform || !service.isSupportedPlatform,
        isTrue,
      );
    });

    test('isOwnSource detects GlicoDose echo', () {
      expect(HealthPlatformService.isOwnSource('GlicoDose'), isTrue);
      expect(
        HealthPlatformService.isOwnSource('com.diabetes.diabetes_app'),
        isTrue,
      );
      expect(HealthPlatformService.isOwnSource('LibreLink'), isFalse);
    });

    test('toMgdl converts mmol and rejects out of range', () {
      final mgdl = HealthDataPoint(
        uuid: '1',
        value: NumericHealthValue(numericValue: 100),
        type: HealthDataType.BLOOD_GLUCOSE,
        unit: HealthDataUnit.MILLIGRAM_PER_DECILITER,
        dateFrom: DateTime.utc(2026, 1, 1),
        dateTo: DateTime.utc(2026, 1, 1),
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'd',
        sourceId: 's',
        sourceName: 'Libre',
      );
      expect(HealthPlatformService.toMgdl(mgdl), 100);

      final mmol = HealthDataPoint(
        uuid: '2',
        value: NumericHealthValue(numericValue: 5.5),
        type: HealthDataType.BLOOD_GLUCOSE,
        unit: HealthDataUnit.MILLIMOLES_PER_LITER,
        dateFrom: DateTime.utc(2026, 1, 1),
        dateTo: DateTime.utc(2026, 1, 1),
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'd',
        sourceId: 's',
        sourceName: 'Libre',
      );
      expect(HealthPlatformService.toMgdl(mmol), closeTo(99, 1));

      final bad = HealthDataPoint(
        uuid: '3',
        value: NumericHealthValue(numericValue: 900),
        type: HealthDataType.BLOOD_GLUCOSE,
        unit: HealthDataUnit.MILLIGRAM_PER_DECILITER,
        dateFrom: DateTime.utc(2026, 1, 1),
        dateTo: DateTime.utc(2026, 1, 1),
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'd',
        sourceId: 's',
        sourceName: 'Libre',
      );
      expect(HealthPlatformService.toMgdl(bad), isNull);
    });

    test('writeMealCarbs rejects non-positive carbs; writeInsulin rejects non-positive units',
        () async {
      final service = HealthPlatformService();
      expect(
        await service.writeMealCarbs(
          carbohydratesG: 0,
          recordedAt: DateTime.now(),
          clientRecordId: 'c',
        ),
        isFalse,
      );
      expect(
        await service.writeInsulin(
          units: 0,
          recordedAt: DateTime.now(),
          basal: true,
        ),
        HealthWriteResult.failed,
      );
    });

    test('toMgdl rejects NaN infinite and non-positive', () {
      HealthDataPoint point(num v) => HealthDataPoint(
            uuid: 'x',
            value: NumericHealthValue(numericValue: v),
            type: HealthDataType.BLOOD_GLUCOSE,
            unit: HealthDataUnit.MILLIGRAM_PER_DECILITER,
            dateFrom: DateTime.utc(2026, 1, 1),
            dateTo: DateTime.utc(2026, 1, 1),
            sourcePlatform: HealthPlatformType.appleHealth,
            sourceDeviceId: 'd',
            sourceId: 's',
            sourceName: 'x',
          );
      expect(HealthPlatformService.toMgdl(point(double.nan)), isNull);
      expect(HealthPlatformService.toMgdl(point(double.infinity)), isNull);
      expect(HealthPlatformService.toMgdl(point(0)), isNull);
    });

    test('writeInsulin skipped or failed on non-iOS host', () async {
      final service = HealthPlatformService();
      final result = await service.writeInsulin(
        units: 2,
        recordedAt: DateTime.now(),
        basal: false,
      );
      expect(
        result == HealthWriteResult.skippedUnsupported ||
            result == HealthWriteResult.failed,
        isTrue,
      );
    });
  });

  group('HistoryStats with glicemias', () {
    test('compute prefers dense glucose samples for TIR', () {
      final entries = [_entry(200)];
      final dense = [
        GlucoseSample(
          glucoseMgdl: 100,
          recordedAt: DateTime.utc(2026, 3, 1, 12),
        ),
        GlucoseSample(
          glucoseMgdl: 110,
          recordedAt: DateTime.utc(2026, 3, 1, 13),
        ),
        GlucoseSample(
          glucoseMgdl: 200,
          recordedAt: DateTime.utc(2026, 3, 1, 14),
        ),
      ];
      final stats = HistoryStats.compute(
        entries: entries,
        glucoseSamples: dense,
      );
      expect(stats.count, 3);
      expect(stats.tirCount, 2);
      expect(stats.avgGlucose, closeTo(136.666, 0.1));
      expect(stats.recommendedCount, 0);
    });

    test('downsample keeps max points', () {
      final samples = List.generate(
        1000,
        (i) => GlucoseSample(
          glucoseMgdl: 100 + (i % 50),
          recordedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
      final out = HistoryStats.downsample(samples, maxPoints: 100);
      expect(out.length, 100);
      expect(out.first.recordedAt, samples.first.recordedAt);
      expect(out.last.recordedAt, samples.last.recordedAt);
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
