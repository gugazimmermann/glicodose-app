import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/services/iob_service.dart';

/// Lightweight dose record persisted for local IOB recomputation (no network).
class IobCachedDose {
  const IobCachedDose({
    required this.id,
    required this.recordedAt,
    required this.appliedU,
  });

  final String id;
  final DateTime recordedAt;
  final double appliedU;

  Map<String, dynamic> toJson() => {
        'id': id,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
        'applied_u': appliedU,
      };

  factory IobCachedDose.fromJson(Map<String, dynamic> json) {
    return IobCachedDose(
      id: json['id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      appliedU: (json['applied_u'] as num).toDouble(),
    );
  }

  Entry toEntry() => Entry(
        id: id,
        userId: 'cache',
        recordedAt: recordedAt,
        glucoseMgdl: 0,
        appliedInsulin: appliedU,
      );
}

/// SharedPreferences-backed IOB dose cache used by foreground ticks and
/// Android Workmanager background updates.
class IobCache {
  IobCache._();

  static const prefsKey = 'iob_live_cache_v1';
  static const _iob = IobService();

  static Future<void> save({
    required List<IobCachedDose> doses,
    required double durationHours,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode({
        'duration_hours': durationHours,
        'doses': doses.map((d) => d.toJson()).toList(),
      }),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  static Future<({List<IobCachedDose> doses, double durationHours})?>
      load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final duration = (map['duration_hours'] as num?)?.toDouble() ?? 4.0;
      final list = (map['doses'] as List<dynamic>? ?? const [])
          .map((e) => IobCachedDose.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return (doses: list, durationHours: duration);
    } catch (_) {
      return null;
    }
  }

  static List<IobCachedDose> fromEntries(List<Entry> entries) {
    final out = <IobCachedDose>[];
    for (final e in entries) {
      final applied = e.appliedInsulin;
      if (applied == null || applied <= 0) continue;
      out.add(
        IobCachedDose(
          id: e.id,
          recordedAt: e.recordedAt,
          appliedU: applied,
        ),
      );
    }
    return out;
  }

  /// Recompute IOB from persisted cache (or empty if none).
  static Future<IobSnapshot> recompute({DateTime? now}) async {
    final cached = await load();
    if (cached == null) return IobSnapshot.empty;
    return compute(
      doses: cached.doses,
      durationHours: cached.durationHours,
      now: now ?? DateTime.now(),
    );
  }

  static IobSnapshot compute({
    required List<IobCachedDose> doses,
    required double durationHours,
    required DateTime now,
  }) {
    if (durationHours <= 0 || doses.isEmpty) return IobSnapshot.empty;
    return _iob.computeIob(
      recentEntries: doses.map((d) => d.toEntry()).toList(),
      durationHours: durationHours,
      now: now,
    );
  }
}
