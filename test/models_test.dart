import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/models/profile.dart';

void main() {
  group('Entry', () {
    final recorded = DateTime.utc(2026, 3, 1, 12);
    final created = DateTime.utc(2026, 3, 1, 12, 1);

    test('fromJson / toInsertJson / toUpdateJson round-trip', () {
      final entry = Entry.fromJson({
        'id': 'e1',
        'user_id': 'u1',
        'recorded_at': recorded.toIso8601String(),
        'glucose_mgdl': 140.6,
        'food_text': 'pão',
        'food_image_path': 'path.jpg',
        'recommended_insulin': 5,
        'applied_insulin': 4.5,
        'gpt_raw_response': {'carboidratos_g': 40},
        'glucose_source': 'manual',
        'health_glucose_uuid': 'hg',
        'health_insulin_uuid': 'hi',
        'health_meal_client_id': 'hm',
        'created_at': created.toIso8601String(),
      });
      expect(entry.glucoseMgdl, 141);
      expect(entry.gptRawResponse?['carboidratos_g'], 40);
      expect(entry.createdAt, isNotNull);

      final insert = entry.toInsertJson();
      expect(insert['id'], 'e1');
      expect(insert['glucose_source'], 'manual');
      expect(insert['health_meal_client_id'], 'hm');

      final update = entry.toUpdateJson();
      expect(update.containsKey('id'), isFalse);
      expect(update['gpt_raw_response'], isA<Map>());
      expect(update['applied_insulin'], 4.5);
    });

    test('fromJson without optional fields', () {
      final entry = Entry.fromJson({
        'id': 'e2',
        'user_id': 'u1',
        'recorded_at': recorded.toIso8601String(),
        'glucose_mgdl': 100,
      });
      expect(entry.gptRawResponse, isNull);
      expect(entry.createdAt, isNull);
      expect(entry.toUpdateJson().containsKey('gpt_raw_response'), isFalse);
    });

    test('copyWith clears and overrides nullable fields', () {
      final entry = Entry(
        id: 'e1',
        userId: 'u1',
        recordedAt: recorded,
        glucoseMgdl: 120,
        appliedInsulin: 2,
        glucoseSource: 'libre',
        healthGlucoseUuid: 'g',
        healthInsulinUuid: 'i',
        healthMealClientId: 'm',
        gptRawResponse: const {'a': 1},
      );
      final cleared = entry.copyWith(
        appliedInsulin: null,
        gptRawResponse: null,
        glucoseSource: null,
        healthGlucoseUuid: null,
        healthInsulinUuid: null,
        healthMealClientId: null,
        glucoseMgdl: 130,
        foodText: 'arroz',
        recommendedInsulin: 3,
        recordedAt: recorded.add(const Duration(hours: 1)),
      );
      expect(cleared.appliedInsulin, isNull);
      expect(cleared.gptRawResponse, isNull);
      expect(cleared.glucoseSource, isNull);
      expect(cleared.healthGlucoseUuid, isNull);
      expect(cleared.healthInsulinUuid, isNull);
      expect(cleared.healthMealClientId, isNull);
      expect(cleared.glucoseMgdl, 130);
      expect(cleared.foodText, 'arroz');
      expect(cleared.recommendedInsulin, 3);
    });
  });

  group('InsulinRecommendation', () {
    test('metaDisplay and confiancaLabel', () {
      const withMeta = InsulinRecommendation(
        carboidratosG: 0,
        correcaoU: 1,
        bolusComidaU: 0,
        insulinaRecomendadaU: 1,
        metaMgdl: 110,
        metaPeriodo: 'dia',
        confianca: 'alta',
      );
      expect(withMeta.metaDisplay, 'Meta aplicada: 110 mg/dL (dia)');
      expect(withMeta.confiancaLabel, 'Alta');

      const low = InsulinRecommendation(
        carboidratosG: 0,
        correcaoU: 0,
        bolusComidaU: 0,
        insulinaRecomendadaU: 0,
        confianca: 'baixa',
      );
      expect(low.confiancaLabel, 'Baixa');
      expect(
        const InsulinRecommendation(
          carboidratosG: 0,
          correcaoU: 0,
          bolusComidaU: 0,
          insulinaRecomendadaU: 0,
          confianca: 'media',
        ).confiancaLabel,
        'Média',
      );
      expect(
        const InsulinRecommendation(
          carboidratosG: 0,
          correcaoU: 0,
          bolusComidaU: 0,
          insulinaRecomendadaU: 0,
        ).confiancaLabel,
        '—',
      );
      expect(
        const InsulinRecommendation(
          carboidratosG: 0,
          correcaoU: 0,
          bolusComidaU: 0,
          insulinaRecomendadaU: 0,
          metaMgdl: 100,
        ).metaDisplay,
        'Meta aplicada: 100 mg/dL',
      );
    });

    test('fromJson tolerates NaN and recommended_insulin alias', () {
      final rec = InsulinRecommendation.fromJson({
        'carboidratos_g': double.nan,
        'correcao_u': double.infinity,
        'bolus_comida_u': 'x',
        'recommended_insulin': 7,
        'iob_u': 1,
        'observacao': 'ok',
        'meta_mgdl': 110,
        'meta_periodo': 'noite',
        'horario_br': '22:00',
        'confianca': 'media',
      });
      expect(rec.carboidratosG, 0);
      expect(rec.correcaoU, 0);
      expect(rec.bolusComidaU, 0);
      expect(rec.insulinaRecomendadaU, 7);
      expect(rec.source, 'ai');
      expect(rec.metaPeriodo, 'noite');
    });

    test('fromEntry prefers gpt payload then falls back', () {
      final withGpt = Entry(
        id: 'e1',
        userId: 'u1',
        recordedAt: DateTime.utc(2026, 1, 1),
        glucoseMgdl: 100,
        recommendedInsulin: 9,
        gptRawResponse: {
          'carboidratos_g': 30,
          'correcao_u': 1,
          'bolus_comida_u': 3,
          'insulina_recomendada_u': 4,
        },
      );
      final fromGpt = InsulinRecommendation.fromEntry(withGpt);
      expect(fromGpt.insulinaRecomendadaU, 4);
      expect(fromGpt.carboidratosG, 30);

      final manual = Entry(
        id: 'e2',
        userId: 'u1',
        recordedAt: DateTime.utc(2026, 1, 1),
        glucoseMgdl: 100,
        recommendedInsulin: 8,
      );
      final fromManual = InsulinRecommendation.fromEntry(manual);
      expect(fromManual.source, 'manual');
      expect(fromManual.insulinaRecomendadaU, 8);

      final badGpt = Entry(
        id: 'e3',
        userId: 'u1',
        recordedAt: DateTime.utc(2026, 1, 1),
        glucoseMgdl: 100,
        recommendedInsulin: 2,
        gptRawResponse: const {},
      );
      expect(
        InsulinRecommendation.fromEntry(badGpt).insulinaRecomendadaU,
        2,
      );
    });

    test('copyWith overrides selected fields', () {
      const base = InsulinRecommendation(
        carboidratosG: 10,
        correcaoU: 1,
        bolusComidaU: 2,
        insulinaRecomendadaU: 3,
        iobU: 0.5,
      );
      final next = base.copyWith(
        carboidratosG: 20,
        correcaoU: 0,
        bolusComidaU: 1,
        insulinaRecomendadaU: 1,
        iobU: 0,
        observacao: 'n',
        source: 'local',
        metaMgdl: 100,
        metaPeriodo: 'dia',
        horarioBr: '12:00',
        confianca: 'alta',
        raw: const {'x': 1},
      );
      expect(next.carboidratosG, 20);
      expect(next.source, 'local');
      expect(next.raw?['x'], 1);
    });
  });

  group('LibreGlucoseReading', () {
    test('fromJson parses camel and snake flags', () {
      final reading = LibreGlucoseReading.fromJson({
        'glucose_mgdl': 95.4,
        'trend': 3,
        'isHigh': true,
        'is_low': false,
        'recorded_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'patient_id': 'p1',
      });
      expect(reading.glucoseMgdl, 95);
      expect(reading.isHigh, isTrue);
      expect(reading.trendLabel, '→');
      expect(reading.ageLabel, contains('min'));
      expect(reading.patientId, 'p1');
    });

    test('trendLabel and ageLabel edge cases', () {
      expect(const LibreGlucoseReading(glucoseMgdl: 100, trend: 1).trendLabel, '↓↓');
      expect(const LibreGlucoseReading(glucoseMgdl: 100, trend: 2).trendLabel, '↓');
      expect(const LibreGlucoseReading(glucoseMgdl: 100, trend: 4).trendLabel, '↑');
      expect(const LibreGlucoseReading(glucoseMgdl: 100, trend: 5).trendLabel, '↑↑');
      expect(const LibreGlucoseReading(glucoseMgdl: 100, trend: 9).trendLabel, '');

      expect(const LibreGlucoseReading(glucoseMgdl: 100).ageLabel, '');
      final now = LibreGlucoseReading(
        glucoseMgdl: 100,
        recordedAt: DateTime.now(),
      );
      expect(now.ageLabel, 'agora');
      final hours = LibreGlucoseReading(
        glucoseMgdl: 100,
        recordedAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      expect(hours.ageLabel, contains('h'));
      final days = LibreGlucoseReading(
        glucoseMgdl: 100,
        recordedAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(days.ageLabel, contains('d'));

      final invalid = LibreGlucoseReading.fromJson({
        'glucose_mgdl': 100,
        'recorded_at': 'not-a-date',
      });
      expect(invalid.recordedAt, isNull);
    });

    test('LibreConnectionStatus.disconnected', () {
      expect(LibreConnectionStatus.disconnected.connected, isFalse);
    });
  });

  group('BasalDose', () {
    test('toInsertJson and copyWith clear helpers', () {
      final dose = BasalDose(
        id: 'b1',
        userId: 'u1',
        recordedAt: DateTime.utc(2026, 9, 21, 22),
        units: 18,
        insulinName: 'Lantus',
        notes: 'noite',
        createdAt: DateTime.utc(2026, 9, 21, 22, 1),
      );
      final insert = dose.toInsertJson();
      expect(insert.containsKey('id'), isFalse);
      expect(insert['units'], 18);

      final cleared = dose.copyWith(
        clearInsulinName: true,
        clearNotes: true,
        units: 20,
        recordedAt: DateTime.utc(2026, 9, 22),
      );
      expect(cleared.insulinName, isNull);
      expect(cleared.notes, isNull);
      expect(cleared.units, 20);

      final renamed = dose.copyWith(insulinName: 'Tresiba', notes: 'manhã');
      expect(renamed.insulinName, 'Tresiba');
      expect(renamed.notes, 'manhã');
    });
  });

  group('Profile', () {
    test('diabetes labels, theme parse, disclaimer and copyWith clears', () {
      expect(
        const Profile(id: 'u', diabetesType: Profile.diabetesType1)
            .diabetesTypeLabel,
        'tipo 1',
      );
      expect(
        const Profile(id: 'u', diabetesType: Profile.diabetesType2)
            .diabetesTypeLabel,
        'tipo 2',
      );
      expect(
        const Profile(id: 'u', diabetesType: Profile.diabetesOther)
            .diabetesTypeLabel,
        'outro',
      );
      expect(const Profile(id: 'u').diabetesTypeLabel, 'não informado');
      expect(
        const Profile(id: 'u', diabetesType: 'weird').diabetesTypeLabel,
        'weird',
      );

      final full = Profile.fromJson({
        'id': 'u1',
        'timezone': '  Europe/Lisbon  ',
        'theme': 'dark',
        'disclaimer_accepted_at': '2026-01-01T00:00:00.000Z',
        'supporter_expires_at': '2026-12-01T00:00:00.000Z',
        'supporter_updated_at': '2026-06-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-02T00:00:00.000Z',
        'basal_times_minutes': [480, 2000, 'x', 1320],
        'target_glucose_mgdl': 100,
        'target_night_mgdl': 110,
        'isf_mgdl_per_u': 50,
        'ic_ratio': 10,
        'rapid_insulin_name': 'Humalog',
      });
      expect(full.timezone, 'Europe/Lisbon');
      expect(full.theme, 'dark');
      expect(full.hasAcceptedDisclaimer, isTrue);
      // 2000 out of range and 'x' skipped; keeps first two valid minutes.
      expect(full.basalTimesMinutes, [480, 1320]);
      expect(full.isComplete, isTrue);

      final blankTz = Profile.fromJson({'id': 'u', 'timezone': '   '});
      expect(blankTz.timezone, 'America/Sao_Paulo');
      expect(Profile.fromJson({'id': 'u', 'theme': 'light'}).theme, 'light');
      expect(Profile.fromJson({'id': 'u', 'theme': 'nope'}).theme, 'system');

      final json = full.toJson();
      expect(json['disclaimer_accepted_at'], isNotNull);
      expect(json.containsKey('supporter_status'), isFalse);

      final cleared = full.copyWith(
        clearDisclaimer: true,
        clearBasalInsulinName: true,
        clearBasalDoseU: true,
        isfMgdlPerU: 40,
        icRatio: 12,
        healthSyncEnabled: true,
      );
      expect(cleared.disclaimerAcceptedAt, isNull);
      expect(cleared.basalInsulinName, isNull);
      expect(cleared.basalDoseU, isNull);
      expect(cleared.isfMgdlPerU, 40);
      expect(cleared.healthSyncEnabled, isTrue);
    });
  });
}
