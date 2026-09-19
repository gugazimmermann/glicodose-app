class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.diabetesType,
    this.targetGlucoseMgdl,
    this.targetNightMgdl,
    this.nightStartMinute = 1200,
    this.nightEndMinute = 359,
    this.isfMgdlPerU,
    this.icRatio,
    this.rapidInsulinName,
    this.doseStep = 1,
    this.insulinDurationHours = 4,
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
  final double? isfMgdlPerU;
  final double? icRatio;
  final String? rapidInsulinName;
  final double doseStep;
  final double insulinDurationHours;
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
      isfMgdlPerU: (json['isf_mgdl_per_u'] as num?)?.toDouble(),
      icRatio: (json['ic_ratio'] as num?)?.toDouble(),
      rapidInsulinName: json['rapid_insulin_name'] as String?,
      doseStep: (json['dose_step'] as num?)?.toDouble() ?? 1,
      insulinDurationHours:
          (json['insulin_duration_hours'] as num?)?.toDouble() ?? 4,
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
      'isf_mgdl_per_u': isfMgdlPerU,
      'ic_ratio': icRatio,
      'rapid_insulin_name': rapidInsulinName,
      'dose_step': doseStep,
      'insulin_duration_hours': insulinDurationHours,
      if (disclaimerAcceptedAt != null)
        'disclaimer_accepted_at':
            disclaimerAcceptedAt!.toUtc().toIso8601String(),
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
    double? isfMgdlPerU,
    double? icRatio,
    String? rapidInsulinName,
    double? doseStep,
    double? insulinDurationHours,
    DateTime? disclaimerAcceptedAt,
    String? shareCode,
    String? supporterProductId,
    String? supporterStatus,
    String? supporterStore,
    DateTime? supporterExpiresAt,
    DateTime? supporterUpdatedAt,
    bool clearDisclaimer = false,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      diabetesType: diabetesType ?? this.diabetesType,
      targetGlucoseMgdl: targetGlucoseMgdl ?? this.targetGlucoseMgdl,
      targetNightMgdl: targetNightMgdl ?? this.targetNightMgdl,
      nightStartMinute: nightStartMinute ?? this.nightStartMinute,
      nightEndMinute: nightEndMinute ?? this.nightEndMinute,
      isfMgdlPerU: isfMgdlPerU ?? this.isfMgdlPerU,
      icRatio: icRatio ?? this.icRatio,
      rapidInsulinName: rapidInsulinName ?? this.rapidInsulinName,
      doseStep: doseStep ?? this.doseStep,
      insulinDurationHours:
          insulinDurationHours ?? this.insulinDurationHours,
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
}
