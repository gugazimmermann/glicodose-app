import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LibreLinkUpService {
  LibreLinkUpService(this._client);

  final SupabaseClient _client;

  Future<LibreConnectionStatus> status() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return LibreConnectionStatus.disconnected;

    final row = await _client
        .from('librelinkup_credentials')
        .select(
          'email, region, patient_id, last_sync_at, last_error',
        )
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return LibreConnectionStatus.disconnected;

    final latest = await latestGlucose();
    DateTime? lastSync;
    final syncRaw = row['last_sync_at'];
    if (syncRaw is String && syncRaw.isNotEmpty) {
      lastSync = DateTime.tryParse(syncRaw)?.toLocal();
    }

    return LibreConnectionStatus(
      connected: true,
      email: row['email'] as String?,
      region: row['region'] as String?,
      patientId: row['patient_id'] as String?,
      lastSyncAt: lastSync,
      lastError: row['last_error'] as String?,
      latest: latest,
    );
  }

  Future<LibreGlucoseReading?> latestGlucose() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('glicemias')
        .select(
          'glucose_mgdl, trend, is_high, is_low, recorded_at, external_id',
        )
        .eq('user_id', userId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return LibreGlucoseReading.fromJson(Map<String, dynamic>.from(row));
  }

  /// Realtime stream of the latest row for the current user.
  Stream<LibreGlucoseReading?> watchLatestGlucose() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream<LibreGlucoseReading?>.value(null);
    }

    return _client
        .from('glicemias')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .map((rows) {
      if (rows.isEmpty) return null;
      return LibreGlucoseReading.fromJson(Map<String, dynamic>.from(rows.first));
    });
  }

  Future<LibreGlucoseReading> connect({
    required String email,
    required String password,
    required String region,
  }) async {
    final response = await _client.functions.invoke(
      'librelinkup-connect',
      body: {
        'email': email.trim(),
        'password': password,
        'region': region,
      },
    );

    if (response.status != 200) {
      throw Exception(_errorMessage(response, 'Falha ao conectar LibreLinkUp'));
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final latest = data['latest'];
    if (latest is Map) {
      return LibreGlucoseReading.fromJson(Map<String, dynamic>.from(latest));
    }
    final fromDb = await latestGlucose();
    if (fromDb != null) return fromDb;
    throw Exception('Conectado, mas sem leitura de glicemia disponível');
  }

  Future<LibreGlucoseReading> syncNow() async {
    final response = await _client.functions.invoke('librelinkup-sync');

    if (response.status != 200) {
      throw Exception(_errorMessage(response, 'Falha ao sincronizar glicemia'));
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    return LibreGlucoseReading.fromJson(data);
  }

  Future<void> disconnect() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('librelinkup_credentials')
        .delete()
        .eq('user_id', userId);
  }

  String _errorMessage(FunctionResponse response, String fallback) {
    final error = response.data;
    if (error is Map && error['error'] != null) {
      return error['error'].toString();
    }
    return '$fallback (${response.status})';
  }
}
