import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/basal_reminder_logic.dart';
import 'package:diabetes_app/services/export_service.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('BasalDose', () {
    test('fromJson / toUpdateJson round-trip fields', () {
      final dose = BasalDose.fromJson({
        'id': 'b1',
        'user_id': 'u1',
        'recorded_at': '2026-09-21T22:00:00.000Z',
        'units': 18.5,
        'insulin_name': 'Lantus',
        'notes': null,
        'created_at': '2026-09-21T22:01:00.000Z',
      });
      expect(dose.id, 'b1');
      expect(dose.units, 18.5);
      expect(dose.insulinName, 'Lantus');
      final json = dose.toUpdateJson();
      expect(json['units'], 18.5);
      expect(json['insulin_name'], 'Lantus');
    });
  });

  group('Profile basal fields', () {
    test('parses basal columns and serializes them', () {
      final profile = Profile.fromJson({
        'id': 'u1',
        'basal_insulin_name': 'Tresiba',
        'basal_dose_u': 20,
        'basal_times_minutes': [480, 1320],
        'basal_reminder_enabled': true,
        'rapid_insulin_name': 'Humalog',
        'target_glucose_mgdl': 100,
        'target_night_mgdl': 110,
        'isf_mgdl_per_u': 50,
        'ic_ratio': 10,
      });
      expect(profile.basalInsulinName, 'Tresiba');
      expect(profile.basalDoseU, 20);
      expect(profile.basalTimesMinutes, [480, 1320]);
      expect(profile.basalReminderEnabled, isTrue);
      expect(profile.isComplete, isTrue);

      final out = profile.toJson();
      expect(out['basal_insulin_name'], 'Tresiba');
      expect(out['basal_dose_u'], 20);
      expect(out['basal_times_minutes'], [480, 1320]);
      expect(out['basal_reminder_enabled'], true);
    });
  });

  group('BasalReminderLogic', () {
    test('normalizeTimes caps at 2 unique sorted minutes', () {
      expect(
        BasalReminderLogic.normalizeTimes([1320, 480, 1320, 2000, -1]),
        [480, 1320],
      );
    });

    test('nextOccurrence rolls to next day when time already passed', () {
      final loc = tz.getLocation('America/Sao_Paulo');
      final from = tz.TZDateTime(loc, 2026, 9, 21, 23, 0);
      final next = BasalReminderLogic.nextOccurrence(
        minutesFromMidnight: 22 * 60,
        location: loc,
        from: from,
      );
      expect(next.day, 22);
      expect(next.hour, 22);
      expect(next.minute, 0);
    });

    test('nextOccurrences returns one per slot', () {
      final loc = tz.getLocation('America/Sao_Paulo');
      final from = tz.TZDateTime(loc, 2026, 9, 21, 8, 0);
      final list = BasalReminderLogic.nextOccurrences(
        timesMinutes: [480, 1320],
        timezone: 'America/Sao_Paulo',
        from: from,
      );
      expect(list, hasLength(2));
      expect(list[0].hour, 8);
      expect(list[1].hour, 22);
    });

    test('formatMinutes', () {
      expect(BasalReminderLogic.formatMinutes(0), '00:00');
      expect(BasalReminderLogic.formatMinutes(1320), '22:00');
    });
  });

  group('ExportService basal', () {
    test('CSV includes kind column and basal rows', () {
      final csv = const ExportService().buildCsv(
        const [],
        basalDoses: [
          BasalDose(
            id: 'b1',
            userId: 'u1',
            recordedAt: DateTime.utc(2026, 9, 21, 22),
            units: 18,
            insulinName: 'Lantus',
          ),
        ],
      );
      expect(csv, contains('kind,recorded_at'));
      expect(csv, contains('basal,'));
      expect(csv, contains('18'));
      expect(csv, contains('Lantus'));
    });
  });
}
