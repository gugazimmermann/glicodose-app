import 'dart:math';

import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/libre_alert_service.dart';
import 'package:diabetes_app/services/theme_preference_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

  /// Same alphabet as `public.generate_share_code()` (no I/O/0/1).
  static const _shareCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _fallbackShareCode() {
    final rnd = Random.secure();
    return List.generate(
      6,
      (_) => _shareCodeAlphabet[rnd.nextInt(_shareCodeAlphabet.length)],
    ).join();
  }

  Future<void> _applyProfilePrefs(Profile profile, {bool applyTheme = true}) async {
    AppTime.setLocation(profile.timezone);
    if (applyTheme) {
      await ThemePreferenceService.save(
        ThemePreferenceService.decode(profile.theme),
      );
    }
    await LibreAlertService.applyFromProfile(profile);
  }

  Future<Profile?> fetchCurrent({bool applyTheme = true}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    var data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data == null || data['share_code'] == null) {
      try {
        await _client.rpc('ensure_share_code');
      } catch (_) {
        // Older DBs may not create the row; upsert will include a code.
      }
      data = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
    }

    final profile = Profile.fromJson(data);
    await _applyProfilePrefs(profile, applyTheme: applyTheme);
    return profile;
  }

  /// Realtime stream of the current user's profile row (RLS-filtered).
  Stream<Profile?> watchCurrent({bool applyTheme = true}) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream<Profile?>.value(null);
    }

    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .asyncMap((rows) async {
      if (rows.isEmpty) return null;
      final profile = Profile.fromJson(Map<String, dynamic>.from(rows.first));
      await _applyProfilePrefs(profile, applyTheme: applyTheme);
      return profile;
    });
  }

  Future<Profile> upsert(Profile profile) async {
    var toSave = profile;
    if (toSave.shareCode == null || toSave.shareCode!.trim().isEmpty) {
      String? code;
      try {
        final raw = await _client.rpc('ensure_share_code');
        if (raw is String && raw.trim().isNotEmpty) code = raw.trim();
      } catch (_) {
        // Fall through to client-generated code for insert.
      }
      toSave = toSave.copyWith(shareCode: code ?? _fallbackShareCode());
    }

    final data = await _client
        .from('profiles')
        .upsert(toSave.toJson())
        .select()
        .single();
    final saved = Profile.fromJson(data);
    await _applyProfilePrefs(saved);
    return saved;
  }

  Future<Profile> acceptDisclaimer() async {
    final current = await fetchCurrent();
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado');
    }

    final updated = (current ?? Profile(id: userId)).copyWith(
      disclaimerAcceptedAt: DateTime.now().toUtc(),
    );
    return upsert(updated);
  }
}
