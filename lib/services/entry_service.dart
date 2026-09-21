import 'dart:typed_data';

import 'package:diabetes_app/models/entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class EntriesPage {
  const EntriesPage({
    required this.entries,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Entry> entries;
  final int total;
  final int page;
  final int pageSize;

  int get totalPages => total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
  bool get hasPrev => page > 0;
  bool get hasNext => page + 1 < totalPages;
}

class EntryService {
  EntryService(this._client);

  final SupabaseClient _client;
  static const _bucket = 'food-photos';
  static const defaultPageSize = 50;

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

  Future<EntriesPage> listEntriesPage({
    int page = 0,
    int pageSize = defaultPageSize,
    bool ascending = false,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return EntriesPage(
        entries: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
      );
    }

    final safePage = page < 0 ? 0 : page;
    final from = safePage * pageSize;
    final to = from + pageSize - 1;

    final response = await _client
        .from('entries')
        .select()
        .eq('user_id', userId)
        .order('recorded_at', ascending: ascending)
        .range(from, to)
        .count(CountOption.exact);

    final rows = response.data as List? ?? const [];
    final entries = rows
        .map((e) => Entry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return EntriesPage(
      entries: entries,
      total: response.count,
      page: safePage,
      pageSize: pageSize,
    );
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
    String? glucoseSource,
    String? healthGlucoseUuid,
    String? healthInsulinUuid,
    String? healthMealClientId,
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
      glucoseSource: glucoseSource,
      healthGlucoseUuid: healthGlucoseUuid,
      healthInsulinUuid: healthInsulinUuid,
      healthMealClientId: healthMealClientId,
    );

    final data = await _client
        .from('entries')
        .insert(entry.toInsertJson())
        .select()
        .single();
    return Entry.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Entry> updateEntry(Entry entry) async {
    final data = await _client
        .from('entries')
        .update(entry.toUpdateJson())
        .eq('id', entry.id)
        .select()
        .single();
    return Entry.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteEntry(String entryId, {String? foodImagePath}) async {
    final path = foodImagePath;
    await _client.from('entries').delete().eq('id', entryId);
    if (path != null && path.isNotEmpty) {
      try {
        await _client.storage.from(_bucket).remove([path]);
      } catch (_) {
        // Best-effort: orphaned photos should not block delete.
      }
    }
  }

  /// Latest entry without applied insulin (user may have forgotten to confirm).
  Future<Entry?> latestUnconfirmed({Duration within = const Duration(hours: 6)}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final since = DateTime.now().toUtc().subtract(within);
    final data = await _client
        .from('entries')
        .select()
        .eq('user_id', userId)
        .isFilter('applied_insulin', null)
        .gte('recorded_at', since.toIso8601String())
        .order('recorded_at', ascending: false)
        .limit(1);
    final rows = data as List;
    if (rows.isEmpty) return null;
    return Entry.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }
}
