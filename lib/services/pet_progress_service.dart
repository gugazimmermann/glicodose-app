import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/app_time.dart';
import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/glicemia_service.dart';
import 'package:diabetes_app/services/history_stats.dart';
import 'package:diabetes_app/services/pet_gamification.dart';
import 'package:timezone/timezone.dart' as tz;

class PetSnapshot {
  const PetSnapshot({
    required this.userId,
    required this.displayName,
    required this.mode,
    required this.computation,
    required this.synced,
  });

  final String userId;
  final String? displayName;
  final GamificationMode mode;
  final PetComputation computation;
  final bool synced;

  String get line => mode == GamificationMode.pet
      ? computation.playfulLine
      : computation.quietLine;
}

class FamilyPet {
  const FamilyPet({
    required this.ownerId,
    required this.displayName,
    required this.mood,
    required this.playfulLine,
    required this.quietLine,
    required this.suggestion,
    required this.dropsToday,
    required this.hoursInRangeToday,
    required this.lifetimeDrops,
    required this.careStreakDays,
    required this.streakPaused,
    required this.unlockedIds,
    required this.equippedAccessoryId,
    this.fuelDay,
  });

  final String ownerId;
  final String? displayName;
  final PetMood mood;
  final String playfulLine;
  final String quietLine;
  final String? suggestion;
  final int dropsToday;
  final double hoursInRangeToday;
  final int lifetimeDrops;
  final int careStreakDays;
  final bool streakPaused;
  final List<String> unlockedIds;
  final String? equippedAccessoryId;
  final DateTime? fuelDay;
}

/// Computes the pet from readings and doses, then stores the snapshot so
/// another phone and the family see the same progress. Family reads only
/// this snapshot, never glucose rows.
class PetProgressService {
  PetProgressService(
    this._client, {
    required this.entries,
    required this.glicemias,
  });

  final SupabaseClient _client;
  final EntryService entries;
  final GlicemiaService glicemias;
  final PetGamification _engine = const PetGamification();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const _noticeId = 72020;
  static const _channelId = 'glicodose_pet';

  Future<PetSnapshot?> refresh(Profile profile) async {
    if (profile.gamificationMode == GamificationMode.off) return null;
    final evaluated = await _evaluate(profile);
    final computation = evaluated.computation;
    if (!evaluated.trusted || computation == null) return null;
    var synced = false;
    synced = await _save(profile: profile, computation: computation);
    if (computation.shouldNotify) {
      await _notify(profile.gamificationMode, computation);
    }
    return PetSnapshot(
      userId: profile.id,
      displayName: profile.fullName,
      mode: profile.gamificationMode,
      computation: computation,
      synced: synced,
    );
  }

  /// Same window and saved unlocks as [refresh], without writing progress.
  /// Null when the saved progress could not be read, so the UI keeps the
  /// seals it already showed.
  Future<List<String>?> sealTitles(Profile profile) async {
    if (profile.gamificationMode == GamificationMode.off) return const [];
    try {
      final evaluated = await _evaluate(profile);
      final computation = evaluated.computation;
      if (!evaluated.trusted || computation == null) return null;
      return [
        for (final item in computation.unlocked)
          item.titleFor(profile.gamificationMode),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<({PetComputation? computation, DateTime now, bool trusted})> _evaluate(
    Profile profile,
  ) async {
    AppTime.setLocation(profile.timezone);
    final zonedNow = AppTime.now();
    final now = _wall(zonedNow);
    final loaded = await _loadStored(profile.id);
    if (loaded.failed) {
      return (computation: null, now: now, trusted: false);
    }

    final recentSince = zonedNow.subtract(const Duration(days: 8));
    DateTime since = recentSince;
    final fuelStart = _midnightInstant(loaded.stored.fuelDay);
    final streakStart = _midnightInstant(loaded.stored.streakCursor);
    if (fuelStart != null && fuelStart.isBefore(since)) since = fuelStart;
    if (streakStart != null && streakStart.isBefore(since)) since = streakStart;

    const catchUpLimit = 5000;
    final catchingUp = since.isBefore(
      recentSince.subtract(const Duration(hours: 1)),
    );
    final catchUp = catchingUp
        ? await glicemias.listSince(since, limit: catchUpLimit)
        : const <GlucoseSample>[];
    final recent = await glicemias.listCoveringSince(recentSince);
    final samples = _mergeSamples(catchUp, recent);
    final accountThrough = _accountThrough(
      catchingUp: catchingUp,
      catchUp: catchUp,
      catchUpLimit: catchUpLimit,
      since: since,
      recentSince: recentSince,
    );
    final logged = await entries.listEntriesSince(since);
    final computation = _engine.compute(
      glucose: _glucosePoints(samples, logged),
      logs: [
        for (final entry in logged)
          PetCareLog(
            at: _wall(entry.recordedAt),
            appliedInsulinU: entry.appliedInsulin,
            carbsG: _carbsOf(entry),
          ),
      ],
      now: now,
      stored: loaded.stored,
      nightStartMinute: profile.nightStartMinute,
      nightEndMinute: profile.nightEndMinute,
      staleMinutes: profile.libreAlertStaleMinutes,
      accountThrough: accountThrough,
    );
    return (computation: computation, now: now, trusted: true);
  }

  Future<void> equip(Profile profile, String? accessoryId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('pet_progress').upsert({
      'user_id': userId,
      'equipped_accessory': accessoryId,
      'display_name': profile.fullName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> followerCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    final rows = await _client
        .from('pet_family_links')
        .select('viewer_id')
        .eq('owner_id', userId);
    return (rows as List).length;
  }

  Future<List<FamilyPet>> listFamily() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final links = await _client
        .from('pet_family_links')
        .select('owner_id')
        .eq('viewer_id', userId);
    final ids = [
      for (final raw in links as List) (raw as Map)['owner_id'] as String,
    ];
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('pet_progress')
        .select()
        .inFilter('user_id', ids);
    return [
      for (final raw in rows as List)
        _familyFromJson(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  Future<FamilyPet> follow(String code) async {
    final raw = await _client.rpc(
      'follow_family_pet',
      params: {'p_code': code.trim().toUpperCase()},
    );
    Map<String, dynamic>? row;
    if (raw is List && raw.isNotEmpty) {
      row = Map<String, dynamic>.from(raw.first as Map);
    } else if (raw is Map) {
      row = Map<String, dynamic>.from(raw);
    }
    final ownerId = row?['owner_id'] as String?;
    if (ownerId == null) {
      throw Exception('Não encontrei esse código.');
    }
    final pets = await listFamily();
    for (final pet in pets) {
      if (pet.ownerId == ownerId) return pet;
    }
    return FamilyPet(
      ownerId: ownerId,
      displayName: row?['display_name'] as String?,
      mood: PetMood.sleeping,
      playfulLine: 'Ainda sem um momento gravado.',
      quietLine: 'Ainda sem um momento gravado.',
      suggestion: null,
      dropsToday: 0,
      hoursInRangeToday: 0,
      lifetimeDrops: 0,
      careStreakDays: 0,
      streakPaused: false,
      unlockedIds: const [],
      equippedAccessoryId: null,
    );
  }

  Future<void> unfollow(String ownerId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('pet_family_links')
        .delete()
        .eq('viewer_id', userId)
        .eq('owner_id', ownerId);
  }

  Future<({PetStoredState stored, bool failed})> _loadStored(
    String userId,
  ) async {
    try {
      final row = await _client
          .from('pet_progress')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return (stored: const PetStoredState(), failed: false);
      return (stored: _storedFromJson(row), failed: false);
    } catch (_) {
      return (stored: const PetStoredState(), failed: true);
    }
  }

  Future<bool> _save({
    required Profile profile,
    required PetComputation computation,
  }) async {
    try {
      await _client.from('pet_progress').upsert({
        'user_id': profile.id,
        'fuel_drops_today': computation.dropsOnAccountedDay,
        'hours_in_range_today': computation.hoursInRangeToday,
        'mood': computation.mood.name,
        'playful_line': computation.playfulLine,
        'quiet_line': computation.quietLine,
        'suggestion': computation.suggestion,
        'lifetime_drops': computation.lifetimeDrops,
        'care_streak_days': computation.careStreakDays,
        'streak_paused': computation.streakPaused,
        'streak_cursor': computation.streakCursor == null
            ? null
            : _dateOnly(computation.streakCursor!),
        'unlocked_ids': [for (final item in computation.unlocked) item.id],
        'equipped_accessory': computation.equippedAccessoryId,
        'fuel_day': _dateOnly(computation.accountedDay),
        if (computation.shouldNotify)
          'last_notice_on': _dateOnly(_wall(DateTime.now())),
        'display_name': profile.fullName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _notify(
    GamificationMode mode,
    PetComputation computation,
  ) async {
    if (kIsWeb || computation.newlyUnlocked.isEmpty) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _notifications.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
      );
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'Conquistas',
          description: 'Aviso quando uma conquista nova aparece',
          importance: Importance.defaultImportance,
        ),
      );
      final first = computation.newlyUnlocked.first;
      await _notifications.show(
        id: _noticeId,
        title: first.titleFor(mode),
        body: first.detail,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Conquistas',
            channelDescription: 'Aviso quando uma conquista nova aparece',
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  DateTime? _midnightInstant(DateTime? wallDate) {
    if (wallDate == null) return null;
    return tz.TZDateTime(
      AppTime.location,
      wallDate.year,
      wallDate.month,
      wallDate.day,
    );
  }

  /// Last fully loaded day when the oldest page stopped before the recent window.
  DateTime? _accountThrough({
    required bool catchingUp,
    required List<GlucoseSample> catchUp,
    required int catchUpLimit,
    required DateTime since,
    required DateTime recentSince,
  }) {
    if (!catchingUp || catchUp.length < catchUpLimit || catchUp.isEmpty) {
      return null;
    }
    final lastWall = _wall(catchUp.last.recordedAt);
    if (!lastWall.isBefore(_wall(recentSince))) return null;
    final partialDay = DateTime(lastWall.year, lastWall.month, lastWall.day);
    final previous = partialDay.subtract(const Duration(days: 1));
    final sinceWall = _wall(since);
    final wantedDay = DateTime(sinceWall.year, sinceWall.month, sinceWall.day);
    return previous.isBefore(wantedDay) ? partialDay : previous;
  }

  List<GlucoseSample> _mergeSamples(
    List<GlucoseSample> older,
    List<GlucoseSample> newer,
  ) {
    final seen = <int>{};
    final merged = <GlucoseSample>[];
    for (final sample in [...older, ...newer]) {
      if (seen.add(sample.recordedAt.toUtc().millisecondsSinceEpoch)) {
        merged.add(sample);
      }
    }
    merged.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return merged;
  }

  PetStoredState _storedFromJson(Map<String, dynamic> json) {
    return PetStoredState(
      lifetimeDrops: (json['lifetime_drops'] as num?)?.toInt() ?? 0,
      dropsSavedToday: (json['fuel_drops_today'] as num?)?.toInt() ?? 0,
      fuelDay: _parseDate(json['fuel_day']),
      careStreakDays: (json['care_streak_days'] as num?)?.toInt() ?? 0,
      streakPaused: json['streak_paused'] == true,
      streakCursor: _parseDate(json['streak_cursor']),
      unlockedIds: _ids(json['unlocked_ids']),
      equippedAccessoryId: json['equipped_accessory'] as String?,
      lastNoticeOn: _parseDate(json['last_notice_on']),
    );
  }

  FamilyPet _familyFromJson(Map<String, dynamic> json) {
    final moodName = json['mood'] as String?;
    return FamilyPet(
      ownerId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      mood: PetMood.values.firstWhere(
        (mood) => mood.name == moodName,
        orElse: () => PetMood.sleeping,
      ),
      playfulLine: (json['playful_line'] as String?) ?? '',
      quietLine: (json['quiet_line'] as String?) ?? '',
      suggestion: json['suggestion'] as String?,
      dropsToday: (json['fuel_drops_today'] as num?)?.toInt() ?? 0,
      hoursInRangeToday:
          (json['hours_in_range_today'] as num?)?.toDouble() ?? 0,
      lifetimeDrops: (json['lifetime_drops'] as num?)?.toInt() ?? 0,
      careStreakDays: (json['care_streak_days'] as num?)?.toInt() ?? 0,
      streakPaused: json['streak_paused'] == true,
      unlockedIds: _ids(json['unlocked_ids']).toList(),
      equippedAccessoryId: json['equipped_accessory'] as String?,
      fuelDay: _parseDate(json['fuel_day']),
    );
  }

  Set<String> _ids(dynamic raw) {
    if (raw is! List) return {};
    return {for (final item in raw) item.toString()};
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _dateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<PetGlucosePoint> _glucosePoints(
    List<GlucoseSample> samples,
    List<Entry> logged,
  ) {
    final points = <PetGlucosePoint>[];
    final sensorMinutes = <DateTime>{};
    for (final sample in samples) {
      final at = _wall(sample.recordedAt);
      points.add(PetGlucosePoint(at: at, glucoseMgdl: sample.glucoseMgdl));
      sensorMinutes.add(_minute(at));
    }
    for (final entry in logged) {
      final at = _wall(entry.recordedAt);
      if (sensorMinutes.contains(_minute(at))) continue;
      points.add(PetGlucosePoint(at: at, glucoseMgdl: entry.glucoseMgdl));
    }
    return points;
  }

  DateTime _minute(DateTime at) =>
      DateTime(at.year, at.month, at.day, at.hour, at.minute);

  DateTime _wall(DateTime instant) {
    final zoned = AppTime.fromUtc(instant);
    return DateTime(
      zoned.year,
      zoned.month,
      zoned.day,
      zoned.hour,
      zoned.minute,
      zoned.second,
    );
  }

  double? _carbsOf(Entry entry) {
    final raw = entry.gptRawResponse?['carboidratos_g'];
    if (raw is num) return raw.toDouble();
    return null;
  }
}
