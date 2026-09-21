import 'package:timezone/timezone.dart' as tz;

import 'package:diabetes_app/services/app_time.dart';

/// Pure helpers for basal reminder scheduling (testable without plugins).
class BasalReminderLogic {
  BasalReminderLogic._();

  static const maxTimes = 2;
  static const notificationIds = [72101, 72102];

  /// Normalize to at most [maxTimes] unique minutes in [0, 1439], sorted.
  static List<int> normalizeTimes(Iterable<int> raw) {
    final seen = <int>{};
    final out = <int>[];
    for (final m in raw) {
      if (m < 0 || m > 1439) continue;
      if (seen.add(m)) out.add(m);
      if (out.length >= maxTimes) break;
    }
    out.sort();
    return out;
  }

  /// Next daily fire for [minutesFromMidnight] at or after [from] in [location].
  static tz.TZDateTime nextOccurrence({
    required int minutesFromMidnight,
    required tz.Location location,
    tz.TZDateTime? from,
  }) {
    final now = from ?? tz.TZDateTime.now(location);
    final hour = minutesFromMidnight ~/ 60;
    final minute = minutesFromMidnight % 60;
    var candidate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  /// Scheduled instants (one per time slot) for daily basal reminders.
  static List<tz.TZDateTime> nextOccurrences({
    required List<int> timesMinutes,
    String? timezone,
    tz.TZDateTime? from,
  }) {
    AppTime.ensureInitialized();
    final location = timezone != null && timezone.trim().isNotEmpty
        ? _locationOrDefault(timezone.trim())
        : AppTime.location;
    final base = from ?? tz.TZDateTime.now(location);
    return normalizeTimes(timesMinutes)
        .map(
          (m) => nextOccurrence(
            minutesFromMidnight: m,
            location: location,
            from: base,
          ),
        )
        .toList();
  }

  static String formatMinutes(int minutesFromMidnight) {
    final h = (minutesFromMidnight ~/ 60).toString().padLeft(2, '0');
    final m = (minutesFromMidnight % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  static tz.Location _locationOrDefault(String iana) {
    try {
      return tz.getLocation(iana);
    } catch (_) {
      return AppTime.location;
    }
  }
}
