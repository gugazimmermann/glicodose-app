class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.diabetesType,
    this.targetGlucoseMgdl,
    this.targetNightMgdl,
    this.nightStartMinute = 1200,
    this.nightEndMinute = 359,
    this.timezone = 'America/Sao_Paulo',
    this.theme = 'system',
    this.libreAlertsEnabled = false,
    this.libreAlertHypoMgdl = 70,
    this.libreAlertHyperMgdl = 180,
    this.libreAlertStaleMinutes = 20,
    this.healthSyncEnabled = false,
    this.isfMgdlPerU,
    this.icRatio,
    this.rapidInsulinName,
    this.doseStep = 1,
    this.insulinDurationHours = 4,
    this.basalInsulinName,
    this.basalDoseU,
    this.basalTimesMinutes = const [],
    this.basalReminderEnabled = false,
    this.disclaimerAcceptedAt,
    this.shareCode,
    this.supporterProductId,
    this.supporterStatus = 'none',
    this.supporterStore,
    this.supporterExpiresAt,
    this.supporterUpdatedAt,
    this.createdAt,
    this.updatedAt,
  });

  static const diabetesType1 = 'type_1';
  static const diabetesType2 = 'type_2';
  static const diabetesOther = 'other';

  final String id;
  final String? fullName;
  final String? diabetesType;
  final int? targetGlucoseMgdl;
  final int? targetNightMgdl;
  /// Minutes from midnight (default 20:00 = 1200).
  final int nightStartMinute;
  /// Minutes from midnight (default 05:59 = 359).
  final int nightEndMinute;
  /// IANA timezone for day/night targets and clinical clocks.
  final String timezone;
  /// Appearance: system | light | dark.
  final String theme;
  final bool libreAlertsEnabled;
  final int libreAlertHypoMgdl;
  final int libreAlertHyperMgdl;
  final int libreAlertStaleMinutes;
  final bool healthSyncEnabled;
  final double? isfMgdlPerU;
  final double? icRatio;
  final String? rapidInsulinName;
  final double doseStep;
  final double insulinDurationHours;
  final String? basalInsulinName;
  final double? basalDoseU;
  /// Up to 2 daily times as minutes from midnight.
  final List<int> basalTimesMinutes;
  final bool basalReminderEnabled;
  final DateTime? disclaimerAcceptedAt;
  /// Unique 6-char code (A-Z0-9) for doctor linking.
  final String? shareCode;
  /// Mirrored from RevenueCat (read-only for the client upsert).
  final String? supporterProductId;
  final String supporterStatus;
  final String? supporterStore;
  final DateTime? supporterExpiresAt;
  final DateTime? supporterUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSupporter =>
      supporterStatus == 'active' ||
      supporterStatus == 'grace' ||
      supporterStatus == 'canceled';

  bool get isComplete =>
      targetGlucoseMgdl != null &&
      targetNightMgdl != null &&
      isfMgdlPerU != null &&
      icRatio != null &&
      rapidInsulinName != null &&
      rapidInsulinName!.trim().isNotEmpty;

  bool get hasAcceptedDisclaimer => disclaimerAcceptedAt != null;

  String get diabetesTypeLabel {
    switch (diabetesType) {
      case diabetesType1:
        return 'tipo 1';
      case diabetesType2:
        return 'tipo 2';
      case diabetesOther:
        return 'outro';
      default:
        return diabetesType ?? 'não informado';
    }
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      diabetesType: json['diabetes_type'] as String?,
      targetGlucoseMgdl: json['target_glucose_mgdl'] as int?,
      targetNightMgdl: json['target_night_mgdl'] as int?,
      nightStartMinute: (json['night_start_minute'] as num?)?.toInt() ?? 1200,
      nightEndMinute: (json['night_end_minute'] as num?)?.toInt() ?? 359,
      timezone: (json['timezone'] as String?)?.trim().isNotEmpty == true
          ? (json['timezone'] as String).trim()
          : 'America/Sao_Paulo',
      theme: _parseTheme(json['theme'] as String?),
      libreAlertsEnabled: json['libre_alerts_enabled'] == true,
      libreAlertHypoMgdl:
          (json['libre_alert_hypo_mgdl'] as num?)?.toInt() ?? 70,
      libreAlertHyperMgdl:
          (json['libre_alert_hyper_mgdl'] as num?)?.toInt() ?? 180,
      libreAlertStaleMinutes:
          (json['libre_alert_stale_minutes'] as num?)?.toInt() ?? 20,
      healthSyncEnabled: json['health_sync_enabled'] == true,
      isfMgdlPerU: (json['isf_mgdl_per_u'] as num?)?.toDouble(),
      icRatio: (json['ic_ratio'] as num?)?.toDouble(),
      rapidInsulinName: json['rapid_insulin_name'] as String?,
      doseStep: (json['dose_step'] as num?)?.toDouble() ?? 1,
      insulinDurationHours:
          (json['insulin_duration_hours'] as num?)?.toDouble() ?? 4,
      basalInsulinName: json['basal_insulin_name'] as String?,
      basalDoseU: (json['basal_dose_u'] as num?)?.toDouble(),
      basalTimesMinutes: _parseMinutesList(json['basal_times_minutes']),
      basalReminderEnabled: json['basal_reminder_enabled'] == true,
      disclaimerAcceptedAt: json['disclaimer_accepted_at'] != null
          ? DateTime.parse(json['disclaimer_accepted_at'] as String)
          : null,
      shareCode: json['share_code'] as String?,
      supporterProductId: json['supporter_product_id'] as String?,
      supporterStatus: (json['supporter_status'] as String?) ?? 'none',
      supporterStore: json['supporter_store'] as String?,
      supporterExpiresAt: json['supporter_expires_at'] != null
          ? DateTime.parse(json['supporter_expires_at'] as String)
          : null,
      supporterUpdatedAt: json['supporter_updated_at'] != null
          ? DateTime.parse(json['supporter_updated_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Client upsert payload — never writes supporter_* (webhook-owned).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'diabetes_type': diabetesType,
      'target_glucose_mgdl': targetGlucoseMgdl,
      'target_night_mgdl': targetNightMgdl,
      'night_start_minute': nightStartMinute,
      'night_end_minute': nightEndMinute,
      'timezone': timezone,
      'theme': theme,
      'libre_alerts_enabled': libreAlertsEnabled,
      'libre_alert_hypo_mgdl': libreAlertHypoMgdl,
      'libre_alert_hyper_mgdl': libreAlertHyperMgdl,
      'libre_alert_stale_minutes': libreAlertStaleMinutes,
      'health_sync_enabled': healthSyncEnabled,
      'isf_mgdl_per_u': isfMgdlPerU,
      'ic_ratio': icRatio,
      'rapid_insulin_name': rapidInsulinName,
      'dose_step': doseStep,
      'insulin_duration_hours': insulinDurationHours,
      'basal_insulin_name': basalInsulinName,
      'basal_dose_u': basalDoseU,
      'basal_times_minutes': basalTimesMinutes,
      'basal_reminder_enabled': basalReminderEnabled,
      if (disclaimerAcceptedAt != null)
        'disclaimer_accepted_at':
            disclaimerAcceptedAt!.toUtc().toIso8601String(),
      // share_code is server-owned; include only when already known so upsert
      // never inserts a null into the NOT NULL column.
      if (shareCode != null && shareCode!.trim().isNotEmpty)
        'share_code': shareCode!.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Profile copyWith({
    String? fullName,
    String? diabetesType,
    int? targetGlucoseMgdl,
    int? targetNightMgdl,
    int? nightStartMinute,
    int? nightEndMinute,
    String? timezone,
    String? theme,
    bool? libreAlertsEnabled,
    int? libreAlertHypoMgdl,
    int? libreAlertHyperMgdl,
    int? libreAlertStaleMinutes,
    bool? healthSyncEnabled,
    double? isfMgdlPerU,
    double? icRatio,
    String? rapidInsulinName,
    double? doseStep,
    double? insulinDurationHours,
    String? basalInsulinName,
    double? basalDoseU,
    List<int>? basalTimesMinutes,
    bool? basalReminderEnabled,
    DateTime? disclaimerAcceptedAt,
    String? shareCode,
    String? supporterProductId,
    String? supporterStatus,
    String? supporterStore,
    DateTime? supporterExpiresAt,
    DateTime? supporterUpdatedAt,
    bool clearDisclaimer = false,
    bool clearBasalInsulinName = false,
    bool clearBasalDoseU = false,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      diabetesType: diabetesType ?? this.diabetesType,
      targetGlucoseMgdl: targetGlucoseMgdl ?? this.targetGlucoseMgdl,
      targetNightMgdl: targetNightMgdl ?? this.targetNightMgdl,
      nightStartMinute: nightStartMinute ?? this.nightStartMinute,
      nightEndMinute: nightEndMinute ?? this.nightEndMinute,
      timezone: timezone ?? this.timezone,
      theme: theme ?? this.theme,
      libreAlertsEnabled: libreAlertsEnabled ?? this.libreAlertsEnabled,
      libreAlertHypoMgdl: libreAlertHypoMgdl ?? this.libreAlertHypoMgdl,
      libreAlertHyperMgdl: libreAlertHyperMgdl ?? this.libreAlertHyperMgdl,
      libreAlertStaleMinutes:
          libreAlertStaleMinutes ?? this.libreAlertStaleMinutes,
      healthSyncEnabled: healthSyncEnabled ?? this.healthSyncEnabled,
      isfMgdlPerU: isfMgdlPerU ?? this.isfMgdlPerU,
      icRatio: icRatio ?? this.icRatio,
      rapidInsulinName: rapidInsulinName ?? this.rapidInsulinName,
      doseStep: doseStep ?? this.doseStep,
      insulinDurationHours:
          insulinDurationHours ?? this.insulinDurationHours,
      basalInsulinName: clearBasalInsulinName
          ? null
          : (basalInsulinName ?? this.basalInsulinName),
      basalDoseU: clearBasalDoseU ? null : (basalDoseU ?? this.basalDoseU),
      basalTimesMinutes: basalTimesMinutes ?? this.basalTimesMinutes,
      basalReminderEnabled:
          basalReminderEnabled ?? this.basalReminderEnabled,
      disclaimerAcceptedAt: clearDisclaimer
          ? null
          : (disclaimerAcceptedAt ?? this.disclaimerAcceptedAt),
      shareCode: shareCode ?? this.shareCode,
      supporterProductId: supporterProductId ?? this.supporterProductId,
      supporterStatus: supporterStatus ?? this.supporterStatus,
      supporterStore: supporterStore ?? this.supporterStore,
      supporterExpiresAt: supporterExpiresAt ?? this.supporterExpiresAt,
      supporterUpdatedAt: supporterUpdatedAt ?? this.supporterUpdatedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static String _parseTheme(String? raw) {
    switch (raw?.trim()) {
      case 'light':
      case 'dark':
      case 'system':
        return raw!.trim();
      default:
        return 'system';
    }
  }

  static List<int> _parseMinutesList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <int>[];
    for (final e in raw) {
      if (e is num) {
        final m = e.toInt();
        if (m >= 0 && m <= 1439) out.add(m);
      }
      if (out.length >= 2) break;
    }
    return out;
  }
}
