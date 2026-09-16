import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/utils/dose_format.dart';

class IobContribution {
  const IobContribution({
    required this.entryId,
    required this.appliedU,
    required this.recordedAt,
    required this.remainingU,
  });

  final String entryId;
  final double appliedU;
  final DateTime recordedAt;
  final double remainingU;
}

class IobSnapshot {
  const IobSnapshot({
    required this.iobU,
    required this.contributions,
  });

  final double iobU;
  final List<IobContribution> contributions;

  static const empty = IobSnapshot(iobU: 0, contributions: []);
}

/// Linear IOB model:
/// remaining = max(0, applied * (1 - elapsedHours / durationHours))
class IobService {
  const IobService();

  IobSnapshot computeIob({
    required List<Entry> recentEntries,
    required double durationHours,
    required DateTime now,
  }) {
    if (durationHours <= 0) return IobSnapshot.empty;

    final contributions = <IobContribution>[];
    var total = 0.0;

    for (final entry in recentEntries) {
      final applied = entry.appliedInsulin;
      if (applied == null || applied <= 0) continue;

      final elapsedHours =
          now.difference(entry.recordedAt).inMilliseconds / (1000 * 60 * 60);
      if (elapsedHours < 0 || elapsedHours >= durationHours) continue;

      final remaining = applied * (1 - elapsedHours / durationHours);
      if (remaining <= 0) continue;

      total += remaining;
      contributions.add(
        IobContribution(
          entryId: entry.id,
          appliedU: asWholeDose(applied).toDouble(),
          recordedAt: entry.recordedAt,
          remainingU: asWholeDose(remaining).toDouble(),
        ),
      );
    }

    return IobSnapshot(
      iobU: asWholeDose(total).toDouble(),
      contributions: contributions,
    );
  }
}
