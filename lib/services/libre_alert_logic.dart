import 'package:diabetes_app/models/libre_glucose.dart';

/// Zone for Libre glucose edge-triggered alerts.
enum LibreAlertZone { ok, hypo, hyper }

/// Pure alert decision (unit-testable, no plugins).
class LibreAlertDecision {
  const LibreAlertDecision({
    required this.zone,
    required this.shouldNotify,
    this.title,
    this.body,
    this.notificationId,
  });

  final LibreAlertZone zone;
  final bool shouldNotify;
  final String? title;
  final String? body;
  final int? notificationId;

  static const none = LibreAlertDecision(
    zone: LibreAlertZone.ok,
    shouldNotify: false,
  );
}

/// Shared thresholds + hysteresis for local and server evaluators.
class LibreAlertLogic {
  LibreAlertLogic({
    this.hypoMgdl = 70,
    this.hyperMgdl = 180,
    this.staleMinutes = 20,
    this.realertMinutes = 20,
  });

  final int hypoMgdl;
  final int hyperMgdl;
  final int staleMinutes;
  final int realertMinutes;

  int get hypoClearMgdl => hypoMgdl + 10;
  int get hyperClearMgdl => hyperMgdl - 20;

  static const hypoNotificationId = 73001;
  static const hyperNotificationId = 73002;
  static const staleNotificationId = 73003;

  LibreAlertZone zoneForGlucose(int mgdl, LibreAlertZone previous) {
    switch (previous) {
      case LibreAlertZone.hypo:
        if (mgdl >= hypoClearMgdl) {
          return mgdl > hyperMgdl ? LibreAlertZone.hyper : LibreAlertZone.ok;
        }
        return LibreAlertZone.hypo;
      case LibreAlertZone.hyper:
        if (mgdl <= hyperClearMgdl) {
          return mgdl < hypoMgdl ? LibreAlertZone.hypo : LibreAlertZone.ok;
        }
        return LibreAlertZone.hyper;
      case LibreAlertZone.ok:
        if (mgdl < hypoMgdl) return LibreAlertZone.hypo;
        if (mgdl > hyperMgdl) return LibreAlertZone.hyper;
        return LibreAlertZone.ok;
    }
  }

  /// Decide whether to fire a hypo/hyper notification.
  LibreAlertDecision evaluateReading({
    required LibreGlucoseReading reading,
    required LibreAlertZone previousZone,
    required DateTime now,
    DateTime? lastAlertAt,
    DateTime? lastAlertedRecordedAt,
  }) {
    final at = reading.recordedAt;
    if (at != null && now.difference(at) > Duration(minutes: staleMinutes)) {
      return LibreAlertDecision(zone: previousZone, shouldNotify: false);
    }

    final next = zoneForGlucose(reading.glucoseMgdl, previousZone);
    if (next == LibreAlertZone.ok) {
      return const LibreAlertDecision(
        zone: LibreAlertZone.ok,
        shouldNotify: false,
      );
    }

    final sameSample = lastAlertedRecordedAt != null &&
        at != null &&
        lastAlertedRecordedAt.isAtSameMomentAs(at);
    if (sameSample) {
      return LibreAlertDecision(zone: next, shouldNotify: false);
    }

    final entered = next != previousZone;
    final dueForRealert = lastAlertAt == null ||
        now.difference(lastAlertAt) >= Duration(minutes: realertMinutes);
    if (!entered && !dueForRealert) {
      return LibreAlertDecision(zone: next, shouldNotify: false);
    }

    final trend = reading.trendLabel;
    final trendSuffix = trend.isEmpty ? '' : ' $trend';
    if (next == LibreAlertZone.hypo) {
      return LibreAlertDecision(
        zone: next,
        shouldNotify: true,
        title: 'Glicose baixa',
        body: '${reading.glucoseMgdl} mg/dL$trendSuffix',
        notificationId: hypoNotificationId,
      );
    }
    return LibreAlertDecision(
      zone: next,
      shouldNotify: true,
      title: 'Glicose alta',
      body: '${reading.glucoseMgdl} mg/dL$trendSuffix',
      notificationId: hyperNotificationId,
    );
  }

  /// Stale sensor when no successful sync / fresh sample within [staleMinutes].
  LibreAlertDecision evaluateStale({
    required DateTime now,
    required DateTime? lastSuccessSyncAt,
    required bool libreConnected,
    required bool alertsEnabled,
    DateTime? lastStaleAlertAt,
    DateTime? sampleRecordedAt,
    int consecutiveFailures = 0,
  }) {
    if (!alertsEnabled || !libreConnected) {
      return LibreAlertDecision.none;
    }
    final syncStale = lastSuccessSyncAt == null ||
        now.difference(lastSuccessSyncAt) > Duration(minutes: staleMinutes);
    final sampleStale = sampleRecordedAt != null &&
        now.difference(sampleRecordedAt) > Duration(minutes: staleMinutes);
    final stale =
        syncStale || sampleStale || consecutiveFailures >= 3;
    if (!stale) return LibreAlertDecision.none;

    final due = lastStaleAlertAt == null ||
        now.difference(lastStaleAlertAt) >= Duration(minutes: realertMinutes);
    if (!due) {
      return const LibreAlertDecision(
        zone: LibreAlertZone.ok,
        shouldNotify: false,
      );
    }
    return const LibreAlertDecision(
      zone: LibreAlertZone.ok,
      shouldNotify: true,
      title: 'Sensor sem dados',
      body: 'Não recebemos glicose recente do Libre. Verifique a conexão.',
      notificationId: staleNotificationId,
    );
  }

  static LibreAlertZone zoneFromName(String? raw) {
    switch (raw) {
      case 'hypo':
        return LibreAlertZone.hypo;
      case 'hyper':
        return LibreAlertZone.hyper;
      default:
        return LibreAlertZone.ok;
    }
  }

  static String zoneName(LibreAlertZone z) {
    switch (z) {
      case LibreAlertZone.hypo:
        return 'hypo';
      case LibreAlertZone.hyper:
        return 'hyper';
      case LibreAlertZone.ok:
        return 'ok';
    }
  }
}
