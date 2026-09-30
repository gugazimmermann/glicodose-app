import 'package:diabetes_app/services/history_stats.dart';

/// How the same engine is shown. Off hides it.
enum GamificationMode { off, pet, quiet }

GamificationMode parseGamificationMode(String? raw) {
  switch (raw?.trim()) {
    case 'pet':
      return GamificationMode.pet;
    case 'quiet':
      return GamificationMode.quiet;
    default:
      return GamificationMode.off;
  }
}

String gamificationModeLabel(GamificationMode mode) {
  switch (mode) {
    case GamificationMode.off:
      return 'off';
    case GamificationMode.pet:
      return 'pet';
    case GamificationMode.quiet:
      return 'quiet';
  }
}

enum PetMood { sleeping, curious, celebrating, waiting }

class PetAchievement {
  const PetAchievement({
    required this.id,
    required this.playfulTitle,
    required this.quietTitle,
    required this.detail,
  });

  final String id;
  final String playfulTitle;
  final String quietTitle;
  final String detail;

  String titleFor(GamificationMode mode) =>
      mode == GamificationMode.pet ? playfulTitle : quietTitle;
}

class PetAccessory {
  const PetAccessory({
    required this.id,
    required this.name,
    required this.quietName,
    required this.dropsRequired,
  });

  final String id;
  final String name;
  final String quietName;
  final int dropsRequired;
}

/// One glucose point already expressed in the profile timezone wall clock.
class PetGlucosePoint {
  const PetGlucosePoint({required this.at, required this.glucoseMgdl});

  final DateTime at;
  final int glucoseMgdl;
}

/// A logged dose or meal. Carb grams reward treatment, never a low itself.
class PetCareLog {
  const PetCareLog({required this.at, this.appliedInsulinU, this.carbsG});

  final DateTime at;
  final double? appliedInsulinU;
  final double? carbsG;
}

class PetStoredState {
  const PetStoredState({
    this.lifetimeDrops = 0,
    this.dropsSavedToday = 0,
    this.fuelDay,
    this.careStreakDays = 0,
    this.streakPaused = false,
    this.streakCursor,
    this.unlockedIds = const {},
    this.equippedAccessoryId,
    this.lastNoticeOn,
  });

  final int lifetimeDrops;
  final int dropsSavedToday;
  final DateTime? fuelDay;
  final int careStreakDays;
  final bool streakPaused;
  final DateTime? streakCursor;
  final Set<String> unlockedIds;
  final String? equippedAccessoryId;
  final DateTime? lastNoticeOn;
}

class PetComputation {
  const PetComputation({
    required this.mood,
    required this.playfulLine,
    required this.quietLine,
    required this.suggestion,
    required this.dropsToday,
    required this.hoursInRangeToday,
    required this.lifetimeDrops,
    required this.careStreakDays,
    required this.streakPaused,
    required this.streakCursor,
    required this.unlocked,
    required this.newlyUnlocked,
    required this.equippedAccessoryId,
    required this.shouldNotify,
    required this.accountedDay,
    required this.dropsOnAccountedDay,
  });

  final PetMood mood;
  final String playfulLine;
  final String quietLine;
  final String? suggestion;
  final int dropsToday;
  final double hoursInRangeToday;
  final int lifetimeDrops;
  final int careStreakDays;
  final bool streakPaused;
  final DateTime? streakCursor;
  final List<PetAchievement> unlocked;
  final List<PetAchievement> newlyUnlocked;
  final String? equippedAccessoryId;
  final bool shouldNotify;
  final DateTime accountedDay;
  final int dropsOnAccountedDay;

  static const barDrops = 12;
}

/// Turns time in range and care logs into fuel and achievements.
///
/// The pet never loses accessories or a care streak because a day was
/// outside range. A rough day only pauses the streak.
class PetGamification {
  const PetGamification();

  static const lowMgdl = HistoryStats.tirLowMgdl;
  static const highMgdl = HistoryStats.tirHighMgdl;
  static const accessories = <PetAccessory>[
    PetAccessory(
      id: 'scarf',
      name: 'Lenço',
      quietName: 'Lenço',
      dropsRequired: 3,
    ),
    PetAccessory(
      id: 'glasses',
      name: 'Óculos de explorador',
      quietName: 'Óculos',
      dropsRequired: 8,
    ),
    PetAccessory(
      id: 'cape',
      name: 'Capinha de herói',
      quietName: 'Capinha',
      dropsRequired: 16,
    ),
  ];

  static const achievements = <PetAchievement>[
    PetAchievement(
      id: 'straight_4',
      playfulTitle: 'Primeiros passos da reta',
      quietTitle: '4 h no alvo',
      detail: '4 horas seguidas entre 70 e 180 mg/dL.',
    ),
    PetAchievement(
      id: 'straight_12',
      playfulTitle: 'Monarca da Linha Reta',
      quietTitle: '12 h no alvo',
      detail: '12 horas seguidas entre 70 e 180 mg/dL.',
    ),
    PetAchievement(
      id: 'straight_24',
      playfulTitle: 'Imperador do dia inteiro',
      quietTitle: '24 h no alvo',
      detail: '24 horas seguidas entre 70 e 180 mg/dL.',
    ),
    PetAchievement(
      id: 'night_guardian',
      playfulTitle: 'Guardião da Noite',
      quietTitle: 'Noite no alvo',
      detail: 'Uma noite inteira, na janela do perfil, entre 70 e 180.',
    ),
    PetAchievement(
      id: 'night_guardian_3',
      playfulTitle: 'Três noites no colo',
      quietTitle: 'Três noites no alvo',
      detail: 'Três noites completas no alvo.',
    ),
    PetAchievement(
      id: 'dawn_watch',
      playfulTitle: 'Madrugada mansa',
      quietTitle: '6 h na noite',
      detail: '6 horas seguidas dentro da janela da noite.',
    ),
    PetAchievement(
      id: 'afternoon_calm',
      playfulTitle: 'Tarde de brincadeira',
      quietTitle: 'Tarde no alvo',
      detail: '4 horas seguidas entre 12h e 18h.',
    ),
    PetAchievement(
      id: 'first_log',
      playfulTitle: 'Primeira Anotação',
      quietTitle: 'Primeira dose anotada',
      detail: 'Uma dose aplicada registrada.',
    ),
    PetAchievement(
      id: 'ten_logs',
      playfulTitle: 'Caderno cheio',
      quietTitle: 'Dez doses anotadas',
      detail: 'Dez doses aplicadas registradas.',
    ),
    PetAchievement(
      id: 'breakfast_ritual',
      playfulTitle: 'Ritual do café',
      quietTitle: 'Manhã com dose e carbo',
      detail: 'Dose e carboidrato na mesma refeição da manhã.',
    ),
    PetAchievement(
      id: 'two_meals',
      playfulTitle: 'Duas mesas',
      quietTitle: 'Dois carbos no dia',
      detail:
          'Dois carboidratos no mesmo dia, com pelo menos 3 h de intervalo.',
    ),
    PetAchievement(
      id: 'plate_and_pen',
      playfulTitle: 'Prato e caneta',
      quietTitle: 'Carbo e dose no dia',
      detail: 'Carboidrato e dose aplicada no mesmo dia.',
    ),
    PetAchievement(
      id: 'logger_week',
      playfulTitle: 'Diário da semana',
      quietTitle: 'Doses em 4 dias',
      detail: 'Dose anotada em 4 dias diferentes, nos últimos 7.',
    ),
    PetAchievement(
      id: 'sensor_friend',
      playfulTitle: 'Sensor amigo',
      quietTitle: '24 h de leitura',
      detail: 'Leituras cobrindo 24 horas, sem um buraco grande.',
    ),
    PetAchievement(
      id: 'soft_week',
      playfulTitle: 'Semana inteira',
      quietTitle: '5 dias pela metade',
      detail: '5 dos últimos 7 dias com pelo menos metade do tempo no alvo.',
    ),
    PetAchievement(
      id: 'care_pause',
      playfulTitle: 'Semana que respira',
      quietTitle: 'Sequência em pausa',
      detail: 'Dias de cuidado continuam depois de um dia que só pausou.',
    ),
    PetAchievement(
      id: 'hypo_care',
      playfulTitle: 'Cuidado na queda',
      quietTitle: 'Tratamento anotado',
      detail: 'Carboidrato registrado depois de uma leitura abaixo de 70.',
    ),
    PetAchievement(
      id: 'return_high',
      playfulTitle: 'Volta mansa',
      quietTitle: 'Voltou ao alvo',
      detail: 'Depois de uma leitura acima de 180, a seguinte voltou ao alvo.',
    ),
    PetAchievement(
      id: 'scarf',
      playfulTitle: 'Lenço novo',
      quietTitle: 'Primeiro acessório',
      detail: '3 gotas de combustível acumuladas.',
    ),
    PetAchievement(
      id: 'glasses',
      playfulTitle: 'Óculos de explorador',
      quietTitle: 'Segundo acessório',
      detail: '8 gotas de combustível acumuladas.',
    ),
    PetAchievement(
      id: 'cape',
      playfulTitle: 'Capinha de herói',
      quietTitle: 'Terceiro acessório',
      detail: '16 gotas de combustível acumuladas.',
    ),
  ];

  static PetAchievement? byId(String id) {
    for (final item in achievements) {
      if (item.id == id) return item;
    }
    return null;
  }

  PetComputation compute({
    required List<PetGlucosePoint> glucose,
    required List<PetCareLog> logs,
    required DateTime now,
    required PetStoredState stored,
    int nightStartMinute = 1200,
    int nightEndMinute = 359,
    int staleMinutes = 20,
    DateTime? accountThrough,
  }) {
    const gap = Duration(minutes: 20);
    final points = [...glucose]..sort((a, b) => a.at.compareTo(b.at));
    final today = _dateOnly(now);
    final accountedDay = _accountedDay(today, accountThrough);
    final inRangeRuns = _runs(
      points
          .map(
            (p) => (
              at: p.at,
              keep: p.glucoseMgdl >= lowMgdl && p.glucoseMgdl <= highMgdl,
            ),
          )
          .toList(),
      gap,
    );
    final anyRuns = _runs(
      points.map((p) => (at: p.at, keep: true)).toList(),
      gap,
    );

    final dropsToday = _dropsOverlapping(inRangeRuns, today, now);
    final hoursToday = _hoursOverlapping(inRangeRuns, today, now);
    final lifetime = _nextLifetime(
      stored: stored,
      today: today,
      now: now,
      lastDay: accountedDay,
      inRangeRuns: inRangeRuns,
    );

    final mood = _mood(
      points: points,
      now: now,
      stale: Duration(minutes: staleMinutes),
      dropsToday: dropsToday,
    );
    final lines = _lines(mood, points.isEmpty ? null : points.last);

    final earned = <String>{
      ...stored.unlockedIds,
      ..._earnedFromData(
        points: points,
        logs: logs,
        now: now,
        gap: gap,
        inRangeRuns: inRangeRuns,
        anyRuns: anyRuns,
        nightStartMinute: nightStartMinute,
        nightEndMinute: nightEndMinute,
      ),
    };

    final streak = _foldStreak(
      stored: stored,
      today: today,
      accountThrough: accountedDay,
      inRangeRuns: inRangeRuns,
      anyRuns: anyRuns,
    );
    if (streak.resumedAfterPause && streak.days >= 3) {
      earned.add('care_pause');
    }

    for (final accessory in accessories) {
      if (lifetime >= accessory.dropsRequired) earned.add(accessory.id);
    }

    final unlocked = [
      for (final item in achievements)
        if (earned.contains(item.id)) item,
    ];
    final newly = [
      for (final item in unlocked)
        if (!stored.unlockedIds.contains(item.id)) item,
    ];
    final noticeDay = stored.lastNoticeOn == null
        ? null
        : _dateOnly(stored.lastNoticeOn!);

    return PetComputation(
      mood: mood,
      playfulLine: lines.$1,
      quietLine: lines.$2,
      suggestion: lines.$3,
      dropsToday: dropsToday,
      hoursInRangeToday: hoursToday,
      lifetimeDrops: lifetime,
      careStreakDays: streak.days,
      streakPaused: streak.paused,
      streakCursor: streak.cursor,
      unlocked: unlocked,
      newlyUnlocked: newly,
      equippedAccessoryId: _equipped(stored.equippedAccessoryId, lifetime),
      shouldNotify: newly.isNotEmpty && noticeDay != today,
      accountedDay: accountedDay,
      dropsOnAccountedDay: _dropsOverlapping(
        inRangeRuns,
        accountedDay,
        accountedDay == today ? now : accountedDay.add(const Duration(days: 1)),
      ),
    );
  }

  /// Last day whose hours may move saved fuel and the care streak.
  ///
  /// [accountThrough] is the last fully loaded day when the fetch stopped
  /// short of today. Later days stay out of the saved totals.
  DateTime _accountedDay(DateTime today, DateTime? accountThrough) {
    if (accountThrough == null) return today;
    final day = _dateOnly(accountThrough);
    return day.isAfter(today) ? today : day;
  }

  static bool inRange(int mgdl) => mgdl >= lowMgdl && mgdl <= highMgdl;

  /// Banks every in-range hour from [PetStoredState.fuelDay] through today.
  ///
  /// The saved day only contributes hours above what was already counted.
  /// Later days contribute their full total, so a day the app was closed
  /// still counts once its readings are in the window. With no saved day,
  /// only today is credited.
  int _nextLifetime({
    required PetStoredState stored,
    required DateTime today,
    required DateTime now,
    required DateTime lastDay,
    required List<_Span> inRangeRuns,
  }) {
    int dropsOn(DateTime day) {
      final start = _dateOnly(day);
      final end = start == today ? now : start.add(const Duration(days: 1));
      return _dropsOverlapping(inRangeRuns, start, end);
    }

    final fuelDay = stored.fuelDay == null ? null : _dateOnly(stored.fuelDay!);
    if (fuelDay == null || fuelDay.isAfter(today)) {
      return stored.lifetimeDrops + dropsOn(today);
    }

    var extra = 0;
    final end = lastDay.isBefore(fuelDay) ? fuelDay : lastDay;
    for (
      var day = fuelDay;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      final drops = dropsOn(day);
      if (day == fuelDay) {
        final delta = drops - stored.dropsSavedToday;
        if (delta > 0) extra += delta;
      } else {
        extra += drops;
      }
    }
    return stored.lifetimeDrops + extra;
  }

  String? _equipped(String? current, int lifetime) {
    final owned = [
      for (final item in accessories)
        if (lifetime >= item.dropsRequired) item.id,
    ];
    if (current != null && owned.contains(current)) return current;
    if (owned.isEmpty) return null;
    return owned.last;
  }

  PetMood _mood({
    required List<PetGlucosePoint> points,
    required DateTime now,
    required Duration stale,
    required int dropsToday,
  }) {
    if (points.isEmpty) return PetMood.sleeping;
    final latest = points.last;
    if (now.difference(latest.at) > stale) return PetMood.sleeping;
    if (!inRange(latest.glucoseMgdl)) return PetMood.waiting;
    if (dropsToday >= PetComputation.barDrops) return PetMood.celebrating;
    return PetMood.curious;
  }

  (String, String, String?) _lines(PetMood mood, PetGlucosePoint? latest) {
    switch (mood) {
      case PetMood.sleeping:
        return (
          'Dormindo. Sem leitura recente, e o que já ganhou continua aqui.',
          'Sem leitura recente. O progresso fica guardado.',
          'Quando o sensor voltar, eu acordo.',
        );
      case PetMood.curious:
        return (
          'Curioso. Estou na faixa e juntando combustível.',
          'Na faixa agora.',
          null,
        );
      case PetMood.celebrating:
        return (
          'Barra cheia hoje. Hora de brincar com o que já desbloqueou.',
          '12 horas no alvo hoje.',
          null,
        );
      case PetMood.waiting:
        final low = latest != null && latest.glucoseMgdl < lowMgdl;
        if (low) {
          return (
            'Estou aqui. Se comeu algo para subir, anote o carboidrato.',
            'Fora da faixa. Anote o cuidado, se houver.',
            'Anotar o carboidrato do tratamento.',
          );
        }
        return (
          'Estou esperando, sem pressa. A próxima anotação já ajuda.',
          'Fora da faixa.',
          'Anotar a próxima dose ou olhar o sensor.',
        );
    }
  }

  Set<String> _earnedFromData({
    required List<PetGlucosePoint> points,
    required List<PetCareLog> logs,
    required DateTime now,
    required Duration gap,
    required List<_Span> inRangeRuns,
    required List<_Span> anyRuns,
    required int nightStartMinute,
    required int nightEndMinute,
  }) {
    final earned = <String>{};
    final maxHours = inRangeRuns.fold<double>(
      0,
      (best, run) => _max(best, run.duration.inSeconds / 3600),
    );
    if (maxHours >= 4) earned.add('straight_4');
    if (maxHours >= 12) earned.add('straight_12');
    if (maxHours >= 24) earned.add('straight_24');
    if (_afternoonRun(inRangeRuns)) earned.add('afternoon_calm');
    if (_dawnRun(inRangeRuns, now, nightStartMinute, nightEndMinute)) {
      earned.add('dawn_watch');
    }

    final nights = _recentNights(now, nightStartMinute, nightEndMinute, 7);
    var fullNights = 0;
    for (final night in nights) {
      if (_windowCovered(
        points,
        night.start,
        night.end,
        gap,
        onlyInRange: true,
      )) {
        fullNights++;
      }
    }
    if (fullNights >= 1) earned.add('night_guardian');
    if (fullNights >= 3) earned.add('night_guardian_3');

    if (_windowCovered(
      points,
      now.subtract(const Duration(hours: 24)),
      now,
      gap,
      onlyInRange: false,
    )) {
      earned.add('sensor_friend');
    }
    if (_returnedFromHigh(points)) earned.add('return_high');
    if (_hypoTreated(points, logs)) earned.add('hypo_care');

    final applied = logs.where((l) => (l.appliedInsulinU ?? 0) > 0).toList();
    if (applied.isNotEmpty) earned.add('first_log');
    if (applied.length >= 10) earned.add('ten_logs');
    if (_breakfastRitual(logs)) earned.add('breakfast_ritual');
    if (_twoMeals(logs)) earned.add('two_meals');
    if (_plateAndPen(logs)) earned.add('plate_and_pen');
    if (_loggerWeek(logs, now)) earned.add('logger_week');

    final today = _dateOnly(now);
    var soft = 0;
    for (var i = 1; i <= 7; i++) {
      final day = today.subtract(Duration(days: i));
      if (_dayKind(day, inRangeRuns, anyRuns) == _DayKind.care) soft++;
    }
    if (soft >= 5) earned.add('soft_week');
    return earned;
  }

  bool _afternoonRun(List<_Span> runs) {
    for (final run in runs) {
      var day = _dateOnly(run.start);
      final last = _dateOnly(run.end);
      while (!day.isAfter(last)) {
        final windowStart = DateTime(day.year, day.month, day.day, 12);
        final windowEnd = DateTime(day.year, day.month, day.day, 18);
        if (_overlapHours(run, windowStart, windowEnd) >= 4) return true;
        day = day.add(const Duration(days: 1));
      }
    }
    return false;
  }

  bool _dawnRun(
    List<_Span> runs,
    DateTime now,
    int nightStartMinute,
    int nightEndMinute,
  ) {
    for (final night in _recentNights(
      now,
      nightStartMinute,
      nightEndMinute,
      8,
    )) {
      for (final run in runs) {
        if (_overlapHours(run, night.start, night.end) >= 6) return true;
      }
    }
    return false;
  }

  bool _returnedFromHigh(List<PetGlucosePoint> points) {
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      if (current.glucoseMgdl <= highMgdl) continue;
      if (next.at.difference(current.at) > const Duration(hours: 3)) continue;
      if (inRange(next.glucoseMgdl)) return true;
    }
    return false;
  }

  bool _hypoTreated(List<PetGlucosePoint> points, List<PetCareLog> logs) {
    for (final point in points) {
      if (point.glucoseMgdl >= lowMgdl) continue;
      for (final log in logs) {
        if ((log.carbsG ?? 0) <= 0) continue;
        final delta = log.at.difference(point.at);
        if (!delta.isNegative && delta <= const Duration(minutes: 45)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _breakfastRitual(List<PetCareLog> logs) {
    for (final log in logs) {
      if (log.at.hour < 5 || log.at.hour >= 11) continue;
      if ((log.appliedInsulinU ?? 0) > 0 && (log.carbsG ?? 0) > 0) return true;
    }
    return false;
  }

  bool _twoMeals(List<PetCareLog> logs) {
    final byDay = <DateTime, List<DateTime>>{};
    for (final log in logs) {
      if ((log.carbsG ?? 0) <= 0) continue;
      byDay.putIfAbsent(_dateOnly(log.at), () => []).add(log.at);
    }
    for (final times in byDay.values) {
      times.sort();
      for (var i = 1; i < times.length; i++) {
        if (times[i].difference(times[i - 1]) >= const Duration(hours: 3)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _plateAndPen(List<PetCareLog> logs) {
    final carbs = <DateTime>{};
    final doses = <DateTime>{};
    for (final log in logs) {
      final day = _dateOnly(log.at);
      if ((log.carbsG ?? 0) > 0) carbs.add(day);
      if ((log.appliedInsulinU ?? 0) > 0) doses.add(day);
    }
    for (final day in carbs) {
      if (doses.contains(day)) return true;
    }
    return false;
  }

  bool _loggerWeek(List<PetCareLog> logs, DateTime now) {
    final start = _dateOnly(now).subtract(const Duration(days: 6));
    final days = <DateTime>{};
    for (final log in logs) {
      if ((log.appliedInsulinU ?? 0) <= 0) continue;
      final day = _dateOnly(log.at);
      if (!day.isBefore(start)) days.add(day);
    }
    return days.length >= 4;
  }

  _StreakFold _foldStreak({
    required PetStoredState stored,
    required DateTime today,
    required DateTime accountThrough,
    required List<_Span> inRangeRuns,
    required List<_Span> anyRuns,
  }) {
    var days = stored.careStreakDays;
    var paused = stored.streakPaused;
    var cursor = stored.streakCursor == null
        ? null
        : _dateOnly(stored.streakCursor!);
    final start = cursor == null
        ? today.subtract(const Duration(days: 14))
        : cursor.add(const Duration(days: 1));
    var sawGap = paused;
    var sawCareAfterGap = false;

    final endExclusive = accountThrough.isBefore(today)
        ? accountThrough.add(const Duration(days: 1))
        : today;

    for (
      var day = start;
      day.isBefore(endExclusive) && day.isBefore(today);
      day = day.add(const Duration(days: 1))
    ) {
      final kind = _dayKind(day, inRangeRuns, anyRuns);
      if (kind == _DayKind.uncovered) continue;
      if (kind == _DayKind.care) {
        days += 1;
        paused = false;
        if (sawGap) sawCareAfterGap = true;
      } else {
        paused = true;
        sawGap = true;
      }
      cursor = day;
    }

    return _StreakFold(
      days: days,
      paused: paused,
      cursor: cursor ?? stored.streakCursor,
      resumedAfterPause: sawCareAfterGap,
    );
  }

  /// No readings is not a rough day: it neither grows nor pauses the streak.
  _DayKind _dayKind(
    DateTime day,
    List<_Span> inRangeRuns,
    List<_Span> anyRuns,
  ) {
    final start = _dateOnly(day);
    final end = start.add(const Duration(days: 1));
    final covered = _hoursOverlapping(anyRuns, start, end);
    if (covered < 4) return _DayKind.uncovered;
    final inside = _hoursOverlapping(inRangeRuns, start, end);
    if (inside / covered >= 0.5) return _DayKind.care;
    return _DayKind.rough;
  }

  bool _windowCovered(
    List<PetGlucosePoint> points,
    DateTime start,
    DateTime end,
    Duration gap, {
    required bool onlyInRange,
  }) {
    final inside = [
      for (final point in points)
        if (!point.at.isBefore(start) && !point.at.isAfter(end)) point,
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (inside.isEmpty) return false;
    if (onlyInRange && inside.any((p) => !inRange(p.glucoseMgdl))) return false;
    if (inside.first.at.difference(start) > gap) return false;
    if (end.difference(inside.last.at) > gap) return false;
    for (var i = 1; i < inside.length; i++) {
      if (inside[i].at.difference(inside[i - 1].at) > gap) return false;
    }
    return true;
  }

  List<({DateTime start, DateTime end})> _recentNights(
    DateTime now,
    int nightStartMinute,
    int nightEndMinute,
    int count,
  ) {
    final end = _lastCompletedNightEnd(now, nightStartMinute, nightEndMinute);
    if (end == null) return const [];
    final nights = <({DateTime start, DateTime end})>[];
    var cursor = end;
    for (var i = 0; i < count; i++) {
      final start = _nightStartForEnd(cursor, nightStartMinute);
      if (!start.isBefore(cursor)) break;
      nights.add((start: start, end: cursor));
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return nights;
  }

  DateTime? _lastCompletedNightEnd(
    DateTime now,
    int nightStartMinute,
    int nightEndMinute,
  ) {
    if (nightStartMinute == nightEndMinute) return null;
    final today = _dateOnly(now);
    final endToday = _atMinute(today, nightEndMinute);
    if (!now.isBefore(endToday)) return endToday;
    return _atMinute(today.subtract(const Duration(days: 1)), nightEndMinute);
  }

  DateTime _nightStartForEnd(DateTime end, int nightStartMinute) {
    final sameDay = _atMinute(_dateOnly(end), nightStartMinute);
    if (sameDay.isBefore(end)) return sameDay;
    return _atMinute(
      _dateOnly(end).subtract(const Duration(days: 1)),
      nightStartMinute,
    );
  }

  int _dropsOverlapping(List<_Span> runs, DateTime start, DateTime end) {
    var seconds = 0;
    for (final run in runs) {
      seconds += _overlap(run, start, end).inSeconds;
    }
    if (seconds <= 0) return 0;
    return seconds ~/ 3600;
  }

  double _hoursOverlapping(List<_Span> runs, DateTime start, DateTime end) =>
      runs.fold<int>(
        0,
        (sum, run) => sum + _overlap(run, start, end).inSeconds,
      ) /
      3600;

  double _overlapHours(_Span run, DateTime start, DateTime end) =>
      _overlap(run, start, end).inSeconds / 3600;

  Duration _overlap(_Span run, DateTime start, DateTime end) {
    final from = run.start.isAfter(start) ? run.start : start;
    final to = run.end.isBefore(end) ? run.end : end;
    if (!to.isAfter(from)) return Duration.zero;
    return to.difference(from);
  }

  List<_Span> _runs(List<({DateTime at, bool keep})> points, Duration gap) {
    final sorted = [...points]..sort((a, b) => a.at.compareTo(b.at));
    final out = <_Span>[];
    DateTime? start;
    DateTime? end;
    void close() {
      if (start != null && end != null && end!.isAfter(start!)) {
        out.add(_Span(start!, end!));
      }
      start = null;
      end = null;
    }

    for (final point in sorted) {
      if (!point.keep) {
        close();
        continue;
      }
      if (end == null) {
        start = point.at;
        end = point.at;
        continue;
      }
      if (point.at.difference(end!) <= gap) {
        end = point.at;
      } else {
        close();
        start = point.at;
        end = point.at;
      }
    }
    close();
    return out;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _atMinute(DateTime day, int minute) =>
      DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);

  double _max(double a, double b) => a > b ? a : b;
}

enum _DayKind { uncovered, rough, care }

class _Span {
  const _Span(this.start, this.end);

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

class _StreakFold {
  const _StreakFold({
    required this.days,
    required this.paused,
    required this.cursor,
    required this.resumedAfterPause,
  });

  final int days;
  final bool paused;
  final DateTime? cursor;
  final bool resumedAfterPause;
}
