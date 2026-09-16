import 'dart:typed_data';

import 'package:diabetes_app/models/entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class EntryService {
  EntryService(this._client);

  final SupabaseClient _client;
  static const _bucket = 'food-photos';

  Future<List<Entry>> listEntries({int limit = 50}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _client
        .from('entries')
        .select()
        .eq('user_id', userId)
        .order('recorded_at', ascending: false)
        .limit(limit);

    return (data as List)
        .map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Entry>> listEntriesSince(DateTime since) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final data = await _client
        .from('entries')
        .select()
        .eq('user_id', userId)
        .gte('recorded_at', since.toUtc().toIso8601String())
        .order('recorded_at', ascending: false);

    return (data as List)
        .map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<String> uploadFoodPhoto({
    required String entryId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado');
    }

    final path = '$userId/$entryId.jpg';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return path;
  }

  Future<String?> createSignedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _client.storage.from(_bucket).createSignedUrl(path, 60 * 60);
  }

  Future<Entry> saveEntry({
    required int glucoseMgdl,
    required DateTime recordedAt,
    String? foodText,
    String? foodImagePath,
    double? recommendedInsulin,
    double? appliedInsulin,
    Map<String, dynamic>? gptRawResponse,
    String? entryId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuário não autenticado');
    }

    final entry = Entry(
      id: entryId ?? const Uuid().v4(),
      userId: userId,
      recordedAt: recordedAt,
      glucoseMgdl: glucoseMgdl,
      foodText: foodText,
      foodImagePath: foodImagePath,
      recommendedInsulin: recommendedInsulin,
      appliedInsulin: appliedInsulin,
      gptRawResponse: gptRawResponse,
    );

    final data = await _client
        .from('entries')
        .insert(entry.toInsertJson())
        .select()
        .single();
    return Entry.fromJson(data);
  }

  Future<Entry> updateEntry(Entry entry) async {
    final data = await _client
        .from('entries')
        .update(entry.toUpdateJson())
        .eq('id', entry.id)
        .select()
        .single();
    return Entry.fromJson(data);
  }

  Future<void> deleteEntry(String entryId) async {
    await _client.from('entries').delete().eq('id', entryId);
  }
}
