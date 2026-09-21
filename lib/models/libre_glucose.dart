class LibreGlucoseReading {
  const LibreGlucoseReading({
    required this.glucoseMgdl,
    this.trend,
    this.isHigh = false,
    this.isLow = false,
    this.recordedAt,
    this.patientId,
  });

  final int glucoseMgdl;
  final int? trend;
  final bool isHigh;
  final bool isLow;
  final DateTime? recordedAt;
  final String? patientId;

  factory LibreGlucoseReading.fromJson(Map<String, dynamic> json) {
    final recordedRaw = json['recorded_at'];
    DateTime? recordedAt;
    if (recordedRaw is String && recordedRaw.isNotEmpty) {
      recordedAt = DateTime.tryParse(recordedRaw)?.toLocal();
    }
    return LibreGlucoseReading(
      glucoseMgdl: (json['glucose_mgdl'] as num).round(),
      trend: json['trend'] == null ? null : (json['trend'] as num).round(),
      isHigh: json['is_high'] == true || json['isHigh'] == true,
      isLow: json['is_low'] == true || json['isLow'] == true,
      recordedAt: recordedAt,
      patientId: json['patient_id'] as String?,
    );
  }

  /// Libre TrendArrow 1–5 → short label for UI.
  String get trendLabel {
    switch (trend) {
      case 1:
        return '↓↓';
      case 2:
        return '↓';
      case 3:
        return '→';
      case 4:
        return '↑';
      case 5:
        return '↑↑';
      default:
        return '';
    }
  }

  String get ageLabel {
    final at = recordedAt;
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    return 'há ${diff.inDays} d';
  }
}

class LibreConnectionStatus {
  const LibreConnectionStatus({
    required this.connected,
    this.email,
    this.region,
    this.patientId,
    this.lastSyncAt,
    this.lastError,
    this.latest,
  });

  final bool connected;
  final String? email;
  final String? region;
  final String? patientId;
  final DateTime? lastSyncAt;
  final String? lastError;
  final LibreGlucoseReading? latest;

  static const disconnected = LibreConnectionStatus(connected: false);
}
