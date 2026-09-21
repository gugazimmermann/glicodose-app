class BasalDose {
  const BasalDose({
    required this.id,
    required this.userId,
    required this.recordedAt,
    required this.units,
    this.insulinName,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String userId;
  final DateTime recordedAt;
  final double units;
  final String? insulinName;
  final String? notes;
  final DateTime? createdAt;

  factory BasalDose.fromJson(Map<String, dynamic> json) {
    return BasalDose(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      units: (json['units'] as num).toDouble(),
      insulinName: json['insulin_name'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'units': units,
      'insulin_name': insulinName,
      'notes': notes,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'units': units,
      'insulin_name': insulinName,
      'notes': notes,
    };
  }

  BasalDose copyWith({
    DateTime? recordedAt,
    double? units,
    String? insulinName,
    String? notes,
    bool clearInsulinName = false,
    bool clearNotes = false,
  }) {
    return BasalDose(
      id: id,
      userId: userId,
      recordedAt: recordedAt ?? this.recordedAt,
      units: units ?? this.units,
      insulinName:
          clearInsulinName ? null : (insulinName ?? this.insulinName),
      notes: clearNotes ? null : (notes ?? this.notes),
      createdAt: createdAt,
    );
  }
}
