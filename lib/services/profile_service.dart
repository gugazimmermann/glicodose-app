import 'package:diabetes_app/models/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

  Future<Profile?> fetchCurrent() async {
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

    return Profile.fromJson(data);
  }

  Future<Profile> upsert(Profile profile) async {
    final data = await _client
        .from('profiles')
        .upsert(profile.toJson())
        .select()
        .single();
    return Profile.fromJson(data);
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
