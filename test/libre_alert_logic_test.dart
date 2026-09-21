import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/services/libre_alert_logic.dart';

void main() {
  group('LibreAlertLogic zone hysteresis', () {
    final logic = LibreAlertLogic(hypoMgdl: 70, hyperMgdl: 180);

    test('enters hypo below threshold', () {
      expect(logic.zoneForGlucose(69, LibreAlertZone.ok), LibreAlertZone.hypo);
    });

    test('stays hypo until clear band', () {
      expect(logic.zoneForGlucose(75, LibreAlertZone.hypo), LibreAlertZone.hypo);
      expect(logic.zoneForGlucose(80, LibreAlertZone.hypo), LibreAlertZone.ok);
    });

    test('enters hyper and clears with hysteresis', () {
      expect(
        logic.zoneForGlucose(181, LibreAlertZone.ok),
        LibreAlertZone.hyper,
      );
      expect(
        logic.zoneForGlucose(170, LibreAlertZone.hyper),
        LibreAlertZone.hyper,
      );
      expect(
        logic.zoneForGlucose(160, LibreAlertZone.hyper),
        LibreAlertZone.ok,
      );
    });
  });

  group('LibreAlertLogic evaluateReading', () {
    final logic = LibreAlertLogic();
    final now = DateTime(2026, 9, 21, 12);

    test('notifies on entering hypo', () {
      final d = logic.evaluateReading(
        reading: LibreGlucoseReading(
          glucoseMgdl: 60,
          recordedAt: now,
          trend: 2,
        ),
        previousZone: LibreAlertZone.ok,
        now: now,
      );
      expect(d.shouldNotify, isTrue);
      expect(d.zone, LibreAlertZone.hypo);
      expect(d.notificationId, LibreAlertLogic.hypoNotificationId);
      expect(d.title, 'Glicose baixa');
      expect(d.body, contains('60'));
      expect(d.body, contains('↓'));
    });

    test('debounces same zone within realert window', () {
      final d = logic.evaluateReading(
        reading: LibreGlucoseReading(glucoseMgdl: 55, recordedAt: now),
        previousZone: LibreAlertZone.hypo,
        now: now,
        lastAlertAt: now.subtract(const Duration(minutes: 5)),
      );
      expect(d.shouldNotify, isFalse);
      expect(d.zone, LibreAlertZone.hypo);
    });

    test('realerts after window', () {
      final d = logic.evaluateReading(
        reading: LibreGlucoseReading(glucoseMgdl: 55, recordedAt: now),
        previousZone: LibreAlertZone.hypo,
        now: now,
        lastAlertAt: now.subtract(const Duration(minutes: 21)),
      );
      expect(d.shouldNotify, isTrue);
    });

    test('skips duplicate sample timestamp', () {
      final at = now.subtract(const Duration(minutes: 1));
      final d = logic.evaluateReading(
        reading: LibreGlucoseReading(glucoseMgdl: 55, recordedAt: at),
        previousZone: LibreAlertZone.ok,
        now: now,
        lastAlertedRecordedAt: at,
      );
      expect(d.shouldNotify, isFalse);
    });

    test('does not hypo-notify when sample itself is stale', () {
      final d = logic.evaluateReading(
        reading: LibreGlucoseReading(
          glucoseMgdl: 50,
          recordedAt: now.subtract(const Duration(minutes: 30)),
        ),
        previousZone: LibreAlertZone.ok,
        now: now,
      );
      expect(d.shouldNotify, isFalse);
    });
  });

  group('LibreAlertLogic evaluateStale', () {
    final logic = LibreAlertLogic(staleMinutes: 20);
    final now = DateTime(2026, 9, 21, 12);

    test('notifies when last sync too old', () {
      final d = logic.evaluateStale(
        now: now,
        lastSuccessSyncAt: now.subtract(const Duration(minutes: 25)),
        libreConnected: true,
        alertsEnabled: true,
      );
      expect(d.shouldNotify, isTrue);
      expect(d.notificationId, LibreAlertLogic.staleNotificationId);
    });

    test('notifies on consecutive failures', () {
      final d = logic.evaluateStale(
        now: now,
        lastSuccessSyncAt: now,
        libreConnected: true,
        alertsEnabled: true,
        consecutiveFailures: 3,
      );
      expect(d.shouldNotify, isTrue);
    });

    test('respects stale debounce', () {
      final d = logic.evaluateStale(
        now: now,
        lastSuccessSyncAt: now.subtract(const Duration(minutes: 40)),
        libreConnected: true,
        alertsEnabled: true,
        lastStaleAlertAt: now.subtract(const Duration(minutes: 5)),
      );
      expect(d.shouldNotify, isFalse);
    });

    test('disabled or disconnected skips', () {
      expect(
        logic
            .evaluateStale(
              now: now,
              lastSuccessSyncAt: null,
              libreConnected: true,
              alertsEnabled: false,
            )
            .shouldNotify,
        isFalse,
      );
      expect(
        logic
            .evaluateStale(
              now: now,
              lastSuccessSyncAt: null,
              libreConnected: false,
              alertsEnabled: true,
            )
            .shouldNotify,
        isFalse,
      );
    });

    test('sample age alone can trigger stale', () {
      final d = logic.evaluateStale(
        now: now,
        lastSuccessSyncAt: now,
        sampleRecordedAt: now.subtract(const Duration(minutes: 25)),
        libreConnected: true,
        alertsEnabled: true,
      );
      expect(d.shouldNotify, isTrue);
    });
  });
}
