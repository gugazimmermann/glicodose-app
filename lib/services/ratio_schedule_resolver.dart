/// One pump-style ratio band: active from [startMinute] until the next segment.
class RatioSegment {
  const RatioSegment({
    required this.startMinute,
    required this.value,
  });

  /// Minutes from midnight [0, 1439].
  final int startMinute;

  /// FSI (mg/dL per U) or I:C (g carb per 1 U).
  final double value;

  factory RatioSegment.fromJson(Map<String, dynamic> json) {
    return RatioSegment(
      startMinute: (json['start_minute'] as num?)?.toInt() ?? 0,
      value: (json['value'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'start_minute': startMinute,
        'value': value,
      };

  RatioSegment copyWith({int? startMinute, double? value}) {
    return RatioSegment(
      startMinute: startMinute ?? this.startMinute,
      value: value ?? this.value,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RatioSegment &&
          startMinute == other.startMinute &&
          value == other.value;

  @override
  int get hashCode => Object.hash(startMinute, value);
}

class RatioResolveResult {
  const RatioResolveResult({
    required this.value,
    required this.segment,
    required this.endMinute,
    required this.rangeLabel,
  });

  final double value;
  final RatioSegment segment;

  /// Exclusive end minute (0–1440); 1440 means midnight next day.
  final int endMinute;
  final String rangeLabel;
}

class RatioScheduleResolver {
  const RatioScheduleResolver();

  static const maxSegments = 12;

  /// Sort, clamp, drop invalids/duplicates (keep first), ensure midnight band
  /// when [fallbackValue] is provided and list would otherwise lack start 0.
  List<RatioSegment> normalize(
    List<RatioSegment> raw, {
    double? fallbackValue,
  }) {
    final byStart = <int, RatioSegment>{};
    for (final s in raw) {
      final start = s.startMinute.clamp(0, 1439);
      if (s.value <= 0 || !s.value.isFinite) continue;
      byStart.putIfAbsent(
        start,
        () => RatioSegment(startMinute: start, value: s.value),
      );
      if (byStart.length >= maxSegments) break;
    }
    var list = byStart.values.toList()
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    if (list.isEmpty && fallbackValue != null && fallbackValue > 0) {
      list = [RatioSegment(startMinute: 0, value: fallbackValue)];
    }
    if (list.isNotEmpty && list.first.startMinute != 0) {
      final midnightValue = fallbackValue != null && fallbackValue > 0
          ? fallbackValue
          : list.first.value;
      list = [
        RatioSegment(startMinute: 0, value: midnightValue),
        ...list,
      ];
      // Re-dedupe if we somehow duplicated 0
      final seen = <int>{};
      list = [
        for (final s in list)
          if (seen.add(s.startMinute)) s,
      ];
      if (list.length > maxSegments) {
        list = list.sublist(0, maxSegments);
      }
    }
    return list;
  }

  /// Returns Portuguese error message, or null if valid.
  String? validate(List<RatioSegment> schedule, {String label = 'Faixa'}) {
    if (schedule.isEmpty) {
      return '$label: informe pelo menos uma faixa (começando em 00:00).';
    }
    if (schedule.length > maxSegments) {
      return '$label: no máximo $maxSegments faixas.';
    }
    var hasMidnight = false;
    final starts = <int>{};
    for (final s in schedule) {
      if (s.startMinute < 0 || s.startMinute > 1439) {
        return '$label: horário inválido.';
      }
      if (s.value <= 0 || !s.value.isFinite) {
        return '$label: valor deve ser positivo.';
      }
      if (!starts.add(s.startMinute)) {
        return '$label: horários de início duplicados.';
      }
      if (s.startMinute == 0) hasMidnight = true;
    }
    if (!hasMidnight) {
      return '$label: é obrigatório ter uma faixa começando em 00:00.';
    }
    return null;
  }

  double? mirrorMidnightValue(List<RatioSegment> schedule) {
    for (final s in schedule) {
      if (s.startMinute == 0) return s.value;
    }
    return schedule.isEmpty ? null : schedule.first.value;
  }

  RatioResolveResult? resolve(
    List<RatioSegment> schedule,
    int minuteOfDay, {
    double? fallback,
  }) {
    final minute = ((minuteOfDay % 1440) + 1440) % 1440;
    final normalized = normalize(schedule, fallbackValue: fallback);
    if (normalized.isEmpty) {
      if (fallback != null && fallback > 0) {
        return RatioResolveResult(
          value: fallback,
          segment: RatioSegment(startMinute: 0, value: fallback),
          endMinute: 1440,
          rangeLabel: _rangeLabel(0, 1440),
        );
      }
      return null;
    }

    RatioSegment active = normalized.first;
    for (final s in normalized) {
      if (s.startMinute <= minute) {
        active = s;
      } else {
        break;
      }
    }

    final idx = normalized.indexOf(active);
    final endMinute =
        idx + 1 < normalized.length ? normalized[idx + 1].startMinute : 1440;

    return RatioResolveResult(
      value: active.value,
      segment: active,
      endMinute: endMinute,
      rangeLabel: _rangeLabel(active.startMinute, endMinute),
    );
  }

  static String formatMinute(int minute) {
    final m = ((minute % 1440) + 1440) % 1440;
    final h = m ~/ 60;
    final min = m % 60;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  static String _rangeLabel(int start, int endExclusive) {
    final endLabel = endExclusive >= 1440 ? '24:00' : formatMinute(endExclusive);
    return '${formatMinute(start)}–$endLabel';
  }

  static List<RatioSegment> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <RatioSegment>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        out.add(RatioSegment.fromJson(e));
      } else if (e is Map) {
        out.add(RatioSegment.fromJson(Map<String, dynamic>.from(e)));
      }
      if (out.length >= maxSegments) break;
    }
    return out;
  }
}
