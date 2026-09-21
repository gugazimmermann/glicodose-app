import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/utils/dose_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 21, 12);

  test('notification title format uses whole IOB units', () {
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
    final n = asWholeDose(snap.iobU);
    expect(n, 2);
    expect('~$n U ativas', '~2 U ativas');
  });

  test('zero IOB formats as clear signal', () {
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
    expect(asWholeDose(snap.iobU), 0);
  });
}
