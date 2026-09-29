import 'package:timezone/timezone.dart' as tz;

import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/history_stats.dart';

/// Recurring drop learned from the user's own CGM history.
class GlucoseContextPattern {
  const GlucoseContextPattern({
    required this.weekday,
    required this.hour,
    required this.medianMgdl,
    required this.medianDropMgdl,
    required this.occurrences,
    required this.dropRate,
    this.suggestCarbsG,
  });

  /// ISO weekday: Monday = 1 … Sunday = 7.
  final int weekday;

  /// Local hour 0–23 of the drop.
  final int hour;
  final int medianMgdl;
  final int medianDropMgdl;
  final int occurrences;
  final double dropRate;

  /// 15 when the typical value in this hour is below the hypo threshold.
  final int? suggestCarbsG;

  String get summaryLabel =>
      '${GlucoseContextLogic.weekdayShort(weekday)}, ${hour}h, '
      'queda de cerca de $medianDropMgdl mg/dL';

  factory GlucoseContextPattern.fromJson(Map<String, dynamic> json) {
    final carbs = json['suggest_carbs_g'];
    return GlucoseContextPattern(
      weekday: _asInt(json['weekday']),
      hour: _asInt(json['hour']),
      medianMgdl: _asInt(json['median_mgdl']),
      medianDropMgdl: _asInt(json['median_drop_mgdl']),
      occurrences: _asInt(json['occurrences']),
      dropRate: _asDouble(json['drop_rate']),
      suggestCarbsG: carbs == null ? null : _asInt(carbs),
    );
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.round();
    if (value is String) return num.parse(value).round();
    throw FormatException('inteiro inválido: $value');
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.parse(value);
    throw FormatException('número inválido: $value');
  }
}

/// Local clock used by the lead-window check (profile timezone).
class GlucoseContextClock {
  const GlucoseContextClock({
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.year,
    required this.month,
    required this.day,
  });

  final int weekday;
  final int hour;
  final int minute;
  final int year;
  final int month;
  final int day;
}

/// Notification the cron should send, or nothing when a guard fails.
class GlucoseContextAlert {
  const GlucoseContextAlert({
    required this.pattern,
    required this.slotDate,
    required this.title,
    required this.body,
  });

  final GlucoseContextPattern pattern;

  /// Local calendar date of the pattern hour (`YYYY-MM-DD`).
  final String slotDate;
  final String title;
  final String body;
}

/// Weekday-hour drop patterns. Mirrors `supabase/functions/_shared/glucose_context.ts`.
class GlucoseContextLogic {
  const GlucoseContextLogic({this.hypoMgdl = 70});

  final int hypoMgdl;

  static const lookbackDays = 28;
  static const minDropMgdl = 25;
  static const minOccurrences = 3;
  static const minDropRate = 0.6;
  static const snackCarbsG = 15;
  static const leadMinutes = 20;
  static const mealQuietMinutes = 90;
  static const upperMgdl = 180;
  static const recomputeHours = 6;

  /// Libre trend arrow 5 (↑↑).
  static const strongRiseTrend = 5;

  static const alertTitle = 'Padrão de glicemia';
  static const historyDisclaimer =
      'Padrão do seu histórico. Não substitui a medição nem orientação médica.';

  static const _weekdayFull = <String>[
    '',
    'nas segundas-feiras',
    'nas terças-feiras',
    'nas quartas-feiras',
    'nas quintas-feiras',
    'nas sextas-feiras',
    'nos sábados',
    'nos domingos',
  ];

  static const _weekdayShort = <String>[
    '',
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'domingo',
  ];

  static String weekdayShort(int weekday) {
    if (weekday < 1 || weekday > 7) return '';
    return _weekdayShort[weekday];
  }

  static bool meetsPatternThreshold({
    required int dropDates,
    required int evaluatedDates,
  }) {
    if (evaluatedDates <= 0 || dropDates < minOccurrences) return false;
    return dropDates / evaluatedDates >= minDropRate;
  }

  /// 20 minutes before the pattern hour, in local clock parts.
  static bool isInLeadWindow({
    required int nowWeekday,
    required int nowHour,
    required int nowMinute,
    required int patternWeekday,
    required int patternHour,
  }) {
    final leadHour = patternHour == 0 ? 23 : patternHour - 1;
    final leadWeekday = patternHour == 0
        ? (patternWeekday == 1 ? 7 : patternWeekday - 1)
        : patternWeekday;
    final startMinute = 60 - leadMinutes;
    return nowWeekday == leadWeekday &&
        nowHour == leadHour &&
        nowMinute >= startMinute;
  }

  /// Calendar date of the upcoming pattern hour.
  static String slotDate({
    required int year,
    required int month,
    required int day,
    required int nowHour,
    required int patternHour,
  }) {
    if (patternHour == 0 && nowHour == 23) {
      final next = DateTime(year, month, day).add(const Duration(days: 1));
      return _formatDate(next.year, next.month, next.day);
    }
    return _formatDate(year, month, day);
  }

  static String alertBody(GlucoseContextPattern pattern) {
    final phrase = (pattern.weekday >= 1 && pattern.weekday <= 7)
        ? _weekdayFull[pattern.weekday]
        : 'nesse horário';
    final base =
        'Historicamente, $phrase às ${pattern.hour}h, sua glicemia cai.';
    final carbs = pattern.suggestCarbsG;
    if (carbs == null) return base;
    return '$base Que tal um lanche de ${carbs}g de carboidratos agora?';
  }

  List<GlucoseContextPattern> detect({
    required List<GlucoseSample> samples,
    required String timezone,
    required DateTime now,
  }) {
    final location = _location(timezone);
    final cutoff = now.toUtc().subtract(const Duration(days: lookbackDays));
    final buckets = <String, List<int>>{};

    for (final sample in samples) {
      final at = sample.recordedAt.toUtc();
      if (at.isBefore(cutoff)) continue;
      final local = tz.TZDateTime.from(at, location);
      final key = _bucketKey(local.year, local.month, local.day, local.hour);
      buckets.putIfAbsent(key, () => []).add(sample.glucoseMgdl);
    }

    final hourMedian = <String, int>{
      for (final entry in buckets.entries) entry.key: _median(entry.value),
    };

    final evaluated = <String, int>{};
    final drops = <String, List<_Drop>>{};

    for (final entry in hourMedian.entries) {
      final parts = _parseBucket(entry.key);
      final prev = _previousBucket(parts);
      final prevMedian = hourMedian[prev.key];
      if (prevMedian == null) continue;
      final slot = '${parts.weekday}|${parts.hour}';
      evaluated[slot] = (evaluated[slot] ?? 0) + 1;
      final drop = prevMedian - entry.value;
      if (drop < minDropMgdl) continue;
      drops
          .putIfAbsent(slot, () => [])
          .add(_Drop(hourMgdl: entry.value, dropMgdl: drop));
    }

    final patterns = <GlucoseContextPattern>[];
    for (final entry in evaluated.entries) {
      final slotDrops = drops[entry.key] ?? const <_Drop>[];
      if (!meetsPatternThreshold(
        dropDates: slotDrops.length,
        evaluatedDates: entry.value,
      )) {
        continue;
      }
      final split = entry.key.split('|');
      final weekday = int.parse(split[0]);
      final hour = int.parse(split[1]);
      final medianMgdl = _median(slotDrops.map((d) => d.hourMgdl).toList());
      final medianDrop = _median(slotDrops.map((d) => d.dropMgdl).toList());
      patterns.add(
        GlucoseContextPattern(
          weekday: weekday,
          hour: hour,
          medianMgdl: medianMgdl,
          medianDropMgdl: medianDrop,
          occurrences: slotDrops.length,
          dropRate: slotDrops.length / entry.value,
          suggestCarbsG: medianMgdl < hypoMgdl ? snackCarbsG : null,
        ),
      );
    }

    patterns.sort((a, b) {
      final byDay = a.weekday.compareTo(b.weekday);
      if (byDay != 0) return byDay;
      return a.hour.compareTo(b.hour);
    });
    return patterns;
  }

  /// [lastNotifiedOn] maps `"weekday|hour"` to the slot date already pushed.
  GlucoseContextAlert? evaluateAlert({
    required List<GlucoseContextPattern> patterns,
    required GlucoseContextClock now,
    required int currentMgdl,
    int? trend,
    required bool recentMeal,
    required Map<String, String> lastNotifiedOn,
  }) {
    if (currentMgdl <= hypoMgdl || currentMgdl >= upperMgdl) return null;
    if (trend == strongRiseTrend) return null;
    if (recentMeal) return null;

    final ordered = [...patterns]
      ..sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        if (byDay != 0) return byDay;
        return a.hour.compareTo(b.hour);
      });

    for (final pattern in ordered) {
      if (!isInLeadWindow(
        nowWeekday: now.weekday,
        nowHour: now.hour,
        nowMinute: now.minute,
        patternWeekday: pattern.weekday,
        patternHour: pattern.hour,
      )) {
        continue;
      }
      final slot = slotDate(
        year: now.year,
        month: now.month,
        day: now.day,
        nowHour: now.hour,
        patternHour: pattern.hour,
      );
      final key = '${pattern.weekday}|${pattern.hour}';
      if (lastNotifiedOn[key] == slot) continue;
      return GlucoseContextAlert(
        pattern: pattern,
        slotDate: slot,
        title: alertTitle,
        body: alertBody(pattern),
      );
    }
    return null;
  }

  static tz.Location _location(String timezone) {
    AppTime.ensureInitialized();
    final trimmed = timezone.trim();
    final name = trimmed.isEmpty
        ? AppTime.defaultLocationName
        : (trimmed == 'UTC' ? 'Etc/UTC' : trimmed);
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.getLocation(AppTime.defaultLocationName);
    }
  }

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    final n = sorted.length;
    if (n == 0) {
      throw ArgumentError('median of empty list');
    }
    if (n.isOdd) return sorted[n ~/ 2];
    return ((sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2).round();
  }

  static String _bucketKey(int year, int month, int day, int hour) =>
      '$year-$month-$day|$hour';

  static String _formatDate(int year, int month, int day) {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }

  static _BucketParts _parseBucket(String key) {
    final halves = key.split('|');
    final date = halves[0].split('-');
    final year = int.parse(date[0]);
    final month = int.parse(date[1]);
    final day = int.parse(date[2]);
    final hour = int.parse(halves[1]);
    return _BucketParts(
      year: year,
      month: month,
      day: day,
      hour: hour,
      weekday: DateTime(year, month, day).weekday,
    );
  }

  static _BucketParts _previousBucket(_BucketParts current) {
    if (current.hour > 0) {
      return _BucketParts(
        year: current.year,
        month: current.month,
        day: current.day,
        hour: current.hour - 1,
        weekday: current.weekday,
      );
    }
    final prev = DateTime(
      current.year,
      current.month,
      current.day,
    ).subtract(const Duration(days: 1));
    return _BucketParts(
      year: prev.year,
      month: prev.month,
      day: prev.day,
      hour: 23,
      weekday: prev.weekday,
    );
  }
}

class _Drop {
  const _Drop({required this.hourMgdl, required this.dropMgdl});

  final int hourMgdl;
  final int dropMgdl;
}

class _BucketParts {
  const _BucketParts({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.weekday,
  });

  final int year;
  final int month;
  final int day;
  final int hour;
  final int weekday;

  String get key => GlucoseContextLogic._bucketKey(year, month, day, hour);
}
