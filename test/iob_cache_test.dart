import 'package:diabetes_app/services/iob_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final now = DateTime.utc(2026, 9, 21, 12);

  test('compute: halfway through duration => half IOB', () {
    final snap = IobCache.compute(
      doses: [
        IobCachedDose(
          id: '1',
          recordedAt: now.subtract(const Duration(hours: 2)),
          appliedU: 4,
        ),
      ],
      durationHours: 4,
      now: now,
    );
    expect(snap.iobU, 2);
  });

  test('compute: expired dose => 0', () {
    final snap = IobCache.compute(
      doses: [
        IobCachedDose(
          id: '1',
          recordedAt: now.subtract(const Duration(hours: 5)),
          appliedU: 4,
        ),
      ],
      durationHours: 4,
      now: now,
    );
    expect(snap.iobU, 0);
  });

  test('save/load round-trip and recomputeWithoutNetwork', () async {
    final doses = [
      IobCachedDose(
        id: '1',
        recordedAt: now.subtract(const Duration(hours: 2)),
        appliedU: 4,
      ),
    ];
    await IobCache.save(doses: doses, durationHours: 4);

    final loaded = await IobCache.load();
    expect(loaded, isNotNull);
    expect(loaded!.doses.length, 1);
    expect(loaded.doses.first.appliedU, 4);
    expect(loaded.durationHours, 4);

    final snap = await IobCache.recompute(now: now);
    expect(snap.iobU, 2);
  });

  test('clear removes cache', () async {
    await IobCache.save(
      doses: [
        IobCachedDose(id: '1', recordedAt: now, appliedU: 3),
      ],
      durationHours: 4,
    );
    await IobCache.clear();
    expect(await IobCache.load(), isNull);
    expect((await IobCache.recompute(now: now)).iobU, 0);
  });

  test('tick over time drops whole units', () {
    final recorded = now.subtract(const Duration(minutes: 1));
    final doses = [
      IobCachedDose(id: '1', recordedAt: recorded, appliedU: 4),
    ];

    final justApplied = IobCache.compute(
      doses: doses,
      durationHours: 4,
      now: now,
    );
    expect(justApplied.iobU, 4);

    final afterTwoHours = IobCache.compute(
      doses: doses,
      durationHours: 4,
      now: now.add(const Duration(hours: 2)),
    );
    expect(afterTwoHours.iobU, 2);

    final afterFourHours = IobCache.compute(
      doses: doses,
      durationHours: 4,
      now: now.add(const Duration(hours: 4)),
    );
    expect(afterFourHours.iobU, 0);
  });
}
