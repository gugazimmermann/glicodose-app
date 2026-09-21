import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/history_stats.dart';

/// CGM / Health glucose time-series (`glicemias`).
class GlicemiaService {
  GlicemiaService(this._client);

  final SupabaseClient _client;

  Future<List<GlucoseSample>> listSince(
    DateTime since, {
    int limit = 5000,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('glicemias')
        .select('glucose_mgdl, recorded_at')
        .eq('user_id', userId)
        .gte('recorded_at', since.toUtc().toIso8601String())
        .order('recorded_at', ascending: true)
        .limit(limit);

    return _mapRows(rows as List);
  }

  Future<List<GlucoseSample>> listRecent({int limit = 2000}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('glicemias')
        .select('glucose_mgdl, recorded_at')
        .eq('user_id', userId)
        .order('recorded_at', ascending: false)
        .limit(limit);

    final samples = _mapRows(rows as List);
    return samples.reversed.toList();
  }

  /// Upsert Health / platform readings. Returns number of rows attempted.
  Future<int> upsertHealthReadings(List<PlatformGlucoseReading> readings) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || readings.isEmpty) return 0;

    final rows = <Map<String, dynamic>>[];
    for (final r in readings) {
      rows.add({
        'user_id': userId,
        'recorded_at': r.recordedAt.toUtc().toIso8601String(),
        'glucose_mgdl': r.glucoseMgdl,
        'source': 'health',
        'external_id': r.externalId,
        'raw': {
          'source_name': r.sourceName,
          if (r.uuid != null) 'uuid': r.uuid,
        },
      });
    }

    // Chunk to avoid payload limits.
    const chunk = 200;
    var count = 0;
    for (var i = 0; i < rows.length; i += chunk) {
      final slice = rows.sublist(i, i + chunk > rows.length ? rows.length : i + chunk);
      await _client.from('glicemias').upsert(
            slice,
            onConflict: 'user_id,external_id',
          );
      count += slice.length;
    }
    return count;
  }

  List<GlucoseSample> _mapRows(List rows) {
    final out = <GlucoseSample>[];
    for (final raw in rows) {
      final m = Map<String, dynamic>.from(raw as Map);
      final recordedRaw = m['recorded_at'];
      DateTime? at;
      if (recordedRaw is String) {
        at = DateTime.tryParse(recordedRaw)?.toLocal();
      }
      if (at == null) continue;
      out.add(
        GlucoseSample(
          glucoseMgdl: (m['glucose_mgdl'] as num).round(),
          recordedAt: at,
        ),
      );
    }
    return out;
  }
}
