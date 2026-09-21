import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/libre_alert_service.dart';
import 'package:diabetes_app/services/theme_preference_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

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

    if (data == null) return null;

    if (data['share_code'] == null) {
      await _client.rpc('ensure_share_code');
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

  Future<Profile> upsert(Profile profile) async {
    final data = await _client
        .from('profiles')
        .upsert(profile.toJson())
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
