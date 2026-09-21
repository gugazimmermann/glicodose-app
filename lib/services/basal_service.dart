import 'package:timezone/timezone.dart' as tz;

import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BasalService {
  BasalService(this._client);

  final SupabaseClient _client;

  Future<List<BasalDose>> listDoses({int limit = 200}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _client
        .from('basal_doses')
        .select()
        .eq('user_id', userId)
        .order('recorded_at', ascending: false)
        .limit(limit);

    return (data as List)
        .map((e) => BasalDose.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<BasalDose>> listSince(DateTime since) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _client
        .from('basal_doses')
        .select()
        .eq('user_id', userId)
        .gte('recorded_at', since.toUtc().toIso8601String())
        .order('recorded_at', ascending: false);

    return (data as List)
        .map((e) => BasalDose.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Latest basal logged in the profile's local calendar day, if any.
  Future<BasalDose?> latestToday() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    AppTime.ensureInitialized();
    final now = AppTime.now();
    final startOfDay = tz.TZDateTime(now.location, now.year, now.month, now.day);

    final data = await _client
        .from('basal_doses')
        .select()
        .eq('user_id', userId)
        .gte('recorded_at', startOfDay.toUtc().toIso8601String())
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return BasalDose.fromJson(Map<String, dynamic>.from(data));
  }

  Future<BasalDose> saveDose({
    required double units,
    required DateTime recordedAt,
    String? insulinName,
    String? notes,
    String? id,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado');
    }

    final payload = {
      'user_id': userId,
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'units': units,
      'insulin_name': insulinName,
      'notes': notes,
    };

    if (id == null) {
      final data = await _client
          .from('basal_doses')
          .insert(payload)
          .select()
          .single();
      return BasalDose.fromJson(Map<String, dynamic>.from(data));
    }

    final data = await _client
        .from('basal_doses')
        .update({
          'recorded_at': payload['recorded_at'],
          'units': units,
          'insulin_name': insulinName,
          'notes': notes,
        })
        .eq('id', id)
        .eq('user_id', userId)
        .select()
        .single();
    return BasalDose.fromJson(Map<String, dynamic>.from(data));
  }

  Future<BasalDose> updateDose(BasalDose dose) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado');
    }

    final data = await _client
        .from('basal_doses')
        .update(dose.toUpdateJson())
        .eq('id', dose.id)
        .eq('user_id', userId)
        .select()
        .single();
    return BasalDose.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> deleteDose(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('basal_doses')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }
}
