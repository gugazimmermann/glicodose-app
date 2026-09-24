import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/models/basal_dose.dart';
import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/auth_service.dart';
import 'package:diabetes_app/services/basal_service.dart';
import 'package:diabetes_app/services/dose_reminder_service.dart';
import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/export_service.dart';
import 'package:diabetes_app/services/glicemia_service.dart';
import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/history_stats.dart';
import 'package:diabetes_app/services/insulin_service.dart';
import 'package:diabetes_app/services/iob_badge_service.dart';
import 'package:diabetes_app/services/iob_live_controller.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/services/librelinkup_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/services/push_token_service.dart';
import 'package:diabetes_app/services/speech_service.dart';
import 'package:diabetes_app/services/support_service.dart';

/// In-memory fake graph for widget / smoke tests (no network / plugins).
class FakeAppServices {
  FakeAppServices._(this.services, this.profile, this.entries, this.basal);

  final AppServices services;
  final FakeProfileService profile;
  final FakeEntryService entries;
  final FakeBasalService basal;

  static const userId = '00000000-0000-4000-8000-000000000001';

  static Profile completeProfile({
    String id = userId,
    String? fullName = 'Tester',
  }) {
    return Profile(
      id: id,
      fullName: fullName,
      diabetesType: Profile.diabetesType1,
      targetGlucoseMgdl: 110,
      targetNightMgdl: 120,
      isfMgdlPerU: 50,
      icRatio: 10,
      rapidInsulinName: 'Humalog',
      doseStep: 1,
      insulinDurationHours: 4,
      disclaimerAcceptedAt: DateTime.utc(2026, 1, 1),
      shareCode: 'ABC123',
      basalInsulinName: 'Tresiba',
      basalDoseU: 18,
      basalTimesMinutes: const [480],
      basalReminderEnabled: false,
    );
  }

  static FakeAppServices create({
    Profile? profile,
    List<Entry>? entries,
    List<BasalDose>? basalDoses,
    List<GlucoseSample>? glucoseSamples,
    LibreConnectionStatus? libreStatus,
    FakeHealthPlatformService? health,
  }) {
    final client = Supabase.instance.client;
    final p = FakeProfileService(client, profile: profile ?? completeProfile());
    final e = FakeEntryService(client, seed: entries ?? const []);
    final b = FakeBasalService(client, seed: basalDoses ?? const []);
    final g = FakeGlicemiaService(client, seed: glucoseSamples ?? const []);
    final auth = FakeAuthService(client, userId: userId);
    final insulin = InsulinService(client);
    final speech = FakeSpeechService(client);
    final libre = FakeLibreLinkUpService(
      client,
      statusValue: libreStatus ?? LibreConnectionStatus.disconnected,
    );
    final support = SupportService();
    const export = ExportService();
    final reminders = FakeDoseReminderService();
    final healthSvc = health ?? FakeHealthPlatformService();
    final push = FakePushTokenService(client);
    final badge = FakeIobBadgeService(entries: e, profile: p);
    final iobLive = FakeIobLiveController(
      entries: e,
      profile: p,
      badge: badge,
    );

    final services = AppServices.compose(
      auth: auth,
      profile: p,
      entries: e,
      basal: b,
      glicemias: g,
      insulin: insulin,
      speech: speech,
      libre: libre,
      support: support,
      export: export,
      reminders: reminders,
      healthPlatform: healthSvc,
      pushTokens: push,
      iobBadge: badge,
      iobLive: iobLive,
    );
    return FakeAppServices._(services, p, e, b);
  }
}

class FakeAuthService extends AuthService {
  FakeAuthService(super.client, {required this.userId});

  final String userId;
  bool signedOut = false;

  @override
  User? get currentUser => User(
        id: userId,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00.000Z',
      );

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError('FakeAuthService.signIn');
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError('FakeAuthService.signUp');
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  Future<void> resetPassword(String email) async {}
}

class FakeProfileService extends ProfileService {
  FakeProfileService(super.client, {this.profile});

  Profile? profile;
  int upsertCalls = 0;
  bool throwOnFetch = false;

  @override
  Future<Profile?> fetchCurrent({bool applyTheme = true}) async {
    if (throwOnFetch) throw Exception('fetch failed');
    return profile;
  }

  @override
  Future<Profile> upsert(Profile next) async {
    upsertCalls++;
    profile = next;
    return next;
  }

  @override
  Future<Profile> acceptDisclaimer() async {
    final id = profile?.id ?? FakeAppServices.userId;
    profile = (profile ?? Profile(id: id)).copyWith(
      disclaimerAcceptedAt: DateTime.now().toUtc(),
    );
    return profile!;
  }
}

class FakeEntryService extends EntryService {
  FakeEntryService(super.client, {List<Entry> seed = const []})
      : _entries = List<Entry>.from(seed);

  final List<Entry> _entries;

  List<Entry> get items => List.unmodifiable(_entries);

  @override
  Future<List<Entry>> listEntries({int limit = 50}) async {
    final sorted = [..._entries]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<EntriesPage> listEntriesPage({
    int page = 0,
    int pageSize = EntryService.defaultPageSize,
    bool ascending = false,
  }) async {
    final sorted = [..._entries]
      ..sort(
        (a, b) => ascending
            ? a.recordedAt.compareTo(b.recordedAt)
            : b.recordedAt.compareTo(a.recordedAt),
      );
    final safePage = page < 0 ? 0 : page;
    final from = safePage * pageSize;
    final slice = from >= sorted.length
        ? <Entry>[]
        : sorted.sublist(
            from,
            from + pageSize > sorted.length ? sorted.length : from + pageSize,
          );
    return EntriesPage(
      entries: slice,
      total: sorted.length,
      page: safePage,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<Entry>> listEntriesSince(DateTime since) async {
    return _entries.where((e) => !e.recordedAt.isBefore(since)).toList();
  }

  @override
  Future<String> uploadFoodPhoto({
    required String entryId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async =>
      'fake/$entryId.jpg';

  @override
  Future<String?> createSignedUrl(String? path) async =>
      path == null || path.isEmpty ? null : 'https://example.test/$path';

  @override
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
    final entry = Entry(
      id: entryId ?? 'e-${_entries.length + 1}',
      userId: FakeAppServices.userId,
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
    _entries.insert(0, entry);
    return entry;
  }

  @override
  Future<Entry> updateEntry(Entry entry) async {
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      _entries[i] = entry;
    } else {
      _entries.add(entry);
    }
    return entry;
  }

  @override
  Future<void> deleteEntry(String entryId, {String? foodImagePath}) async {
    _entries.removeWhere((e) => e.id == entryId);
  }

  @override
  Future<Entry?> latestUnconfirmed({
    Duration within = const Duration(hours: 6),
  }) async {
    final since = DateTime.now().toUtc().subtract(within);
    final candidates = _entries
        .where(
          (e) =>
              e.appliedInsulin == null && !e.recordedAt.isBefore(since),
        )
        .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return candidates.isEmpty ? null : candidates.first;
  }
}

class FakeBasalService extends BasalService {
  FakeBasalService(super.client, {List<BasalDose> seed = const []})
      : _doses = List<BasalDose>.from(seed);

  final List<BasalDose> _doses;

  @override
  Future<List<BasalDose>> listDoses({int limit = 200}) async {
    final sorted = [..._doses]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<List<BasalDose>> listSince(DateTime since) async {
    return _doses.where((d) => !d.recordedAt.isBefore(since)).toList();
  }

  @override
  Future<BasalDose?> latestToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    BasalDose? best;
    for (final d in _doses) {
      final local = d.recordedAt.toLocal();
      if (local.isBefore(start) || !local.isBefore(end)) continue;
      if (best == null || d.recordedAt.isAfter(best.recordedAt)) {
        best = d;
      }
    }
    return best;
  }

  @override
  Future<BasalDose> saveDose({
    required double units,
    required DateTime recordedAt,
    String? insulinName,
    String? notes,
    String? id,
  }) async {
    final dose = BasalDose(
      id: id ?? 'b-${_doses.length + 1}',
      userId: FakeAppServices.userId,
      recordedAt: recordedAt,
      units: units,
      insulinName: insulinName,
      notes: notes,
    );
    _doses.insert(0, dose);
    return dose;
  }

  @override
  Future<BasalDose> updateDose(BasalDose dose) async {
    final i = _doses.indexWhere((d) => d.id == dose.id);
    if (i >= 0) {
      _doses[i] = dose;
    } else {
      _doses.add(dose);
    }
    return dose;
  }

  @override
  Future<void> deleteDose(String id) async {
    _doses.removeWhere((d) => d.id == id);
  }
}

class FakeGlicemiaService extends GlicemiaService {
  FakeGlicemiaService(super.client, {List<GlucoseSample> seed = const []})
      : _samples = List<GlucoseSample>.from(seed);

  final List<GlucoseSample> _samples;

  @override
  Future<List<GlucoseSample>> listSince(
    DateTime since, {
    int limit = 5000,
  }) async {
    return _samples
        .where((s) => !s.recordedAt.isBefore(since))
        .take(limit)
        .toList();
  }

  @override
  Future<List<GlucoseSample>> listRecent({int limit = 2000}) async {
    final sorted = [..._samples]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sorted.take(limit).toList().reversed.toList();
  }

  @override
  Future<int> upsertHealthReadings(
    List<PlatformGlucoseReading> readings,
  ) async {
    for (final r in readings) {
      _samples.add(
        GlucoseSample(
          glucoseMgdl: r.glucoseMgdl,
          recordedAt: r.recordedAt,
        ),
      );
    }
    return readings.length;
  }
}

class FakeLibreLinkUpService extends LibreLinkUpService {
  FakeLibreLinkUpService(
    super.client, {
    LibreConnectionStatus statusValue = LibreConnectionStatus.disconnected,
  }) : _status = statusValue;

  LibreConnectionStatus _status;

  @override
  Future<LibreConnectionStatus> status() async => _status;

  @override
  Future<LibreGlucoseReading?> latestGlucose() async => _status.latest;

  @override
  Stream<LibreGlucoseReading?> watchLatestGlucose() =>
      Stream<LibreGlucoseReading?>.value(_status.latest);

  @override
  Future<LibreGlucoseReading> connect({
    required String email,
    required String password,
    required String region,
  }) async {
    final reading = LibreGlucoseReading(
      glucoseMgdl: 120,
      recordedAt: DateTime.now(),
      trend: 3,
    );
    _status = LibreConnectionStatus(
      connected: true,
      email: email,
      region: region,
      latest: reading,
    );
    return reading;
  }

  @override
  Future<LibreGlucoseReading> syncNow() async {
    final latest = _status.latest;
    if (latest != null) return latest;
    throw Exception('Sem leitura Libre');
  }

  @override
  Future<void> disconnect() async {
    _status = LibreConnectionStatus.disconnected;
  }
}

class FakeSpeechService extends SpeechService {
  FakeSpeechService(super.client);

  @override
  Future<void> ensureMicPermission() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<String> stopAndTranscribe() async => 'arroz feijão';

  @override
  Future<void> cancelRecording() async {}
}

class FakeDoseReminderService extends DoseReminderService {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> schedulePostBolusCheck({
    Duration delay = const Duration(hours: 2),
  }) async {}

  @override
  Future<void> cancelPostBolusCheck() async {}

  @override
  Future<void> scheduleBasalReminders({
    required List<int> timesMinutes,
    String? timezone,
    String? insulinName,
    double? doseU,
  }) async {}

  @override
  Future<void> cancelBasalReminders() async {}

  @override
  Future<void> syncBasalFromProfile({
    required bool enabled,
    required List<int> timesMinutes,
    String? timezone,
    String? insulinName,
    double? doseU,
  }) async {}
}

class FakePushTokenService extends PushTokenService {
  FakePushTokenService(super.client);

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}
}

class FakeHealthPlatformService extends HealthPlatformService {
  FakeHealthPlatformService({
    this.supported = false,
    this.avail = HealthPlatformAvailability.unsupported,
    this.label = 'não disponível',
    this.insulinWrite = false,
    this.authorized = false,
    this.latest,
    List<PlatformGlucoseReading>? history,
  }) : history = history ?? const [];

  final bool supported;
  final HealthPlatformAvailability avail;
  final String label;
  final bool insulinWrite;
  bool authorized;
  PlatformGlucoseReading? latest;
  List<PlatformGlucoseReading> history;
  bool syncEnabledRequested = false;

  @override
  bool get isSupportedPlatform => supported;

  @override
  bool get supportsInsulinWrite => insulinWrite;

  @override
  String get platformLabel => label;

  @override
  Future<HealthPlatformAvailability> availability() async => avail;

  @override
  Future<bool> requestAuthorization() async {
    authorized = true;
    return true;
  }

  @override
  Future<bool?> hasAuthorization() async => authorized;

  @override
  Future<List<PlatformGlucoseReading>> glucoseHistory({
    Duration lookback = const Duration(days: 7),
    DateTime? end,
  }) async =>
      history;

  @override
  Future<PlatformGlucoseReading?> latestGlucose({
    Duration lookback = const Duration(days: 7),
  }) async =>
      latest;

  @override
  Future<void> openInstallPage() async {}

  @override
  Future<bool> requestBackgroundAuthorization() async => true;
}

class FakeIobBadgeService extends IobBadgeService {
  FakeIobBadgeService({
    required super.entries,
    required super.profile,
  });

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> ensureNotificationPermission() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> applyCount(int n, {bool skipNotification = false}) async {}
}

class FakeIobLiveController extends IobLiveController {
  FakeIobLiveController({
    required super.entries,
    required super.profile,
    required super.badge,
  });

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<void> clear() async {
    snapshot.value = IobSnapshot.empty;
    failed.value = false;
    loading.value = false;
  }

  @override
  Future<void> refreshFromNetwork() async {
    loading.value = false;
    failed.value = false;
    snapshot.value = IobSnapshot.empty;
  }

  @override
  Future<void> tick() async {}

  @override
  Future<void> ensureWidgetRefreshRunning() async {}
}
