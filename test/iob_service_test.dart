import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:flutter_test/flutter_test.dart';

Entry _entry({
  required String id,
  required DateTime at,
  required double applied,
}) {
  return Entry(
    id: id,
    userId: 'user',
    recordedAt: at,
    glucoseMgdl: 120,
    appliedInsulin: applied,
  );
}

void main() {
  const service = IobService();
  final now = DateTime.utc(2026, 9, 16, 12);

  test('zero doses => IOB 0', () {
    final snap = service.computeIob(
      recentEntries: const [],
      durationHours: 4,
      now: now,
    );
    expect(snap.iobU, 0);
    expect(snap.contributions, isEmpty);
  });

  test('just applied full dose remains ~full', () {
    final snap = service.computeIob(
      recentEntries: [
        _entry(
          id: '1',
          at: now.subtract(const Duration(minutes: 1)),
          applied: 4,
        ),
      ],
      durationHours: 4,
      now: now,
    );
    expect(snap.iobU, 4);
  });

  test('halfway through duration => ~half IOB', () {
    final snap = service.computeIob(
      recentEntries: [
        _entry(id: '1', at: now.subtract(const Duration(hours: 2)), applied: 4),
      ],
      durationHours: 4,
      now: now,
    );
    expect(snap.iobU, 2);
  });

  test('expired dose => 0', () {
    final snap = service.computeIob(
      recentEntries: [
        _entry(id: '1', at: now.subtract(const Duration(hours: 5)), applied: 4),
      ],
      durationHours: 4,
      now: now,
    );
    expect(snap.iobU, 0);
    expect(snap.contributions, isEmpty);
  });

  test('multiple doses sum remaining', () {
    final snap = service.computeIob(
      recentEntries: [
        _entry(id: '1', at: now.subtract(const Duration(hours: 2)), applied: 4),
        _entry(id: '2', at: now.subtract(const Duration(hours: 1)), applied: 2),
      ],
      durationHours: 4,
      now: now,
    );
    // 4 * 0.5 + 2 * 0.75 = 2 + 1.5 = 3.5 -> 4
    expect(snap.iobU, 4);
    expect(snap.contributions.length, 2);
  });

  test('ignores null and zero applied insulin', () {
    final snap = service.computeIob(
      recentEntries: [
        Entry(
          id: '1',
          userId: 'user',
          recordedAt: now.subtract(const Duration(minutes: 10)),
          glucoseMgdl: 100,
        ),
        Entry(
          id: '2',
          userId: 'user',
          recordedAt: now.subtract(const Duration(minutes: 10)),
          glucoseMgdl: 100,
          appliedInsulin: 0,
        ),
      ],
      durationHours: 4,
      now: now,
    );
    expect(snap.iobU, 0);
  });
}
