import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Latest blood glucose reading from Health Connect / Apple Health.
class PlatformGlucoseReading {
  const PlatformGlucoseReading({
    required this.glucoseMgdl,
    required this.recordedAt,
    required this.sourceName,
    this.uuid,
  });

  final int glucoseMgdl;
  final DateTime recordedAt;
  final String sourceName;
  final String? uuid;

  /// Stable id for `glicemias.external_id` / entry dedup.
  String get externalId {
    final u = uuid?.trim();
    if (u != null && u.isNotEmpty) return u;
    return 'health:$sourceName:${recordedAt.toUtc().millisecondsSinceEpoch}';
  }
}

enum HealthPlatformAvailability {
  unsupported,
  unavailable,
  needsInstall,
  ready,
}

enum HealthWriteResult { ok, skippedUnsupported, skippedEcho, failed }

/// Reads/writes blood glucose (and related) via Apple Health / Health Connect.
class HealthPlatformService {
  HealthPlatformService({Health? health}) : _health = health ?? Health();

  final Health _health;
  static const appSourceHints = ['glicodose', 'diabetes_app', 'diabetes app'];

  bool _configured = false;

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get supportsInsulinWrite => isSupportedPlatform && Platform.isIOS;

  String get platformLabel {
    if (kIsWeb) return 'não disponível';
    if (Platform.isIOS) return 'Apple Health';
    if (Platform.isAndroid) return 'Health Connect';
    return 'não disponível';
  }

  List<HealthDataType> get _authTypes {
    final types = <HealthDataType>[
      HealthDataType.BLOOD_GLUCOSE,
      HealthDataType.NUTRITION,
    ];
    if (Platform.isIOS) {
      types.add(HealthDataType.INSULIN_DELIVERY);
    }
    return types;
  }

  List<HealthDataAccess> get _authPermissions {
    final perms = <HealthDataAccess>[
      HealthDataAccess.READ_WRITE,
      HealthDataAccess.WRITE,
    ];
    if (Platform.isIOS) {
      perms.add(HealthDataAccess.WRITE);
    }
    return perms;
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthPlatformAvailability> availability() async {
    if (!isSupportedPlatform) return HealthPlatformAvailability.unsupported;
    await _ensureConfigured();
    if (Platform.isIOS) return HealthPlatformAvailability.ready;
    final status = await _health.getHealthConnectSdkStatus();
    switch (status) {
      case HealthConnectSdkStatus.sdkAvailable:
        return HealthPlatformAvailability.ready;
      case HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
      case HealthConnectSdkStatus.sdkUnavailable:
        return HealthPlatformAvailability.needsInstall;
      case null:
        return HealthPlatformAvailability.unavailable;
    }
  }

  Future<void> openInstallPage() async {
    if (!Platform.isAndroid) return;
    await _ensureConfigured();
    await _health.installHealthConnect();
  }

  /// Requests READ+WRITE access for glucose / nutrition (+ insulin on iOS).
  Future<bool> requestAuthorization() async {
    if (!isSupportedPlatform) return false;
    await _ensureConfigured();
    return await _health.requestAuthorization(
      _authTypes,
      permissions: _authPermissions,
    );
  }

  Future<bool?> hasAuthorization() async {
    if (!isSupportedPlatform) return false;
    await _ensureConfigured();
    return _health.hasPermissions(_authTypes, permissions: _authPermissions);
  }

  Future<bool> requestBackgroundAuthorization() async {
    if (!isSupportedPlatform) return false;
    await _ensureConfigured();
    try {
      return await _health.requestHealthDataInBackgroundAuthorization();
    } catch (_) {
      return false;
    }
  }

  /// Glucose samples in [lookback], newest first. Skips app-authored echo.
  Future<List<PlatformGlucoseReading>> glucoseHistory({
    Duration lookback = const Duration(days: 7),
    DateTime? end,
  }) async {
    if (!isSupportedPlatform) return const [];
    await _ensureConfigured();
    final until = end ?? DateTime.now();
    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.BLOOD_GLUCOSE],
      startTime: until.subtract(lookback),
      endTime: until,
    );
    final out = <PlatformGlucoseReading>[];
    for (final p in points) {
      if (isOwnSource(p.sourceName)) continue;
      final mgdl = toMgdl(p);
      if (mgdl == null) continue;
      out.add(
        PlatformGlucoseReading(
          glucoseMgdl: mgdl,
          recordedAt: p.dateFrom.toLocal(),
          sourceName: p.sourceName.isNotEmpty ? p.sourceName : platformLabel,
          uuid: p.uuid.isNotEmpty ? p.uuid : null,
        ),
      );
    }
    out.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return out;
  }

  /// Latest blood glucose in the last [lookback], newest first.
  Future<PlatformGlucoseReading?> latestGlucose({
    Duration lookback = const Duration(days: 7),
  }) async {
    final list = await glucoseHistory(lookback: lookback);
    return list.isEmpty ? null : list.first;
  }

  /// Write a glucose sample. Returns platform UUID when available.
  Future<String?> writeGlucose({
    required int glucoseMgdl,
    required DateTime recordedAt,
    String? clientRecordId,
  }) async {
    if (!isSupportedPlatform) return null;
    await _ensureConfigured();
    try {
      final uuid = await _health.writeHealthDataUUID(
        value: glucoseMgdl.toDouble(),
        type: HealthDataType.BLOOD_GLUCOSE,
        startTime: recordedAt,
        endTime: recordedAt,
        clientRecordId: clientRecordId,
        recordingMethod: RecordingMethod.manual,
      );
      if (uuid == null || uuid.isEmpty || uuid == 'null') return null;
      return uuid;
    } catch (e, st) {
      debugPrint('HealthPlatformService.writeGlucose failed: $e\n$st');
      return null;
    }
  }

  Future<bool> writeMealCarbs({
    required double carbohydratesG,
    required DateTime recordedAt,
    required String clientRecordId,
    String? name,
  }) async {
    if (!isSupportedPlatform || carbohydratesG <= 0) return false;
    await _ensureConfigured();
    try {
      return await _health.writeMeal(
        mealType: MealType.UNKNOWN,
        startTime: recordedAt,
        endTime: recordedAt,
        carbohydrates: carbohydratesG,
        clientRecordId: clientRecordId,
        name: name ?? 'GlicoDose',
        recordingMethod: RecordingMethod.manual,
      );
    } catch (e, st) {
      debugPrint('HealthPlatformService.writeMealCarbs failed: $e\n$st');
      return false;
    }
  }

  /// Insulin delivery — iOS only. Android returns [HealthWriteResult.skippedUnsupported].
  Future<HealthWriteResult> writeInsulin({
    required double units,
    required DateTime recordedAt,
    required bool basal,
  }) async {
    if (!isSupportedPlatform || units <= 0) {
      return HealthWriteResult.failed;
    }
    if (!supportsInsulinWrite) {
      return HealthWriteResult.skippedUnsupported;
    }
    await _ensureConfigured();
    try {
      final ok = await _health.writeInsulinDelivery(
        units,
        basal ? InsulinDeliveryReason.BASAL : InsulinDeliveryReason.BOLUS,
        recordedAt,
        recordedAt,
      );
      return ok ? HealthWriteResult.ok : HealthWriteResult.failed;
    } catch (e, st) {
      debugPrint('HealthPlatformService.writeInsulin failed: $e\n$st');
      return HealthWriteResult.failed;
    }
  }

  static bool isOwnSource(String sourceName) {
    final lower = sourceName.toLowerCase();
    return appSourceHints.any(lower.contains);
  }

  /// Convert to mg/dL. Health package declares BLOOD_GLUCOSE as mg/dL;
  /// some sources still store mmol/L (~3–30).
  static int? toMgdl(HealthDataPoint point) {
    final value = point.value;
    if (value is! NumericHealthValue) return null;
    final raw = value.numericValue.toDouble();
    if (raw.isNaN || raw.isInfinite || raw <= 0) return null;
    final asMgdl = point.unit == HealthDataUnit.MILLIMOLES_PER_LITER || raw < 35
        ? raw * 18.0182
        : raw;
    final rounded = asMgdl.round();
    if (rounded < 20 || rounded > 600) return null;
    return rounded;
  }
}
