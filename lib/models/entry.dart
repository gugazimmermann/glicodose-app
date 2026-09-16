class Entry {
  const Entry({
    required this.id,
    required this.userId,
    required this.recordedAt,
    required this.glucoseMgdl,
    this.foodText,
    this.foodImagePath,
    this.recommendedInsulin,
    this.appliedInsulin,
    this.gptRawResponse,
    this.createdAt,
  });

  final String id;
  final String userId;
  final DateTime recordedAt;
  final int glucoseMgdl;
  final String? foodText;
  final String? foodImagePath;
  final double? recommendedInsulin;
  final double? appliedInsulin;
  final Map<String, dynamic>? gptRawResponse;
  final DateTime? createdAt;

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      glucoseMgdl: json['glucose_mgdl'] as int,
      foodText: json['food_text'] as String?,
      foodImagePath: json['food_image_path'] as String?,
      recommendedInsulin: (json['recommended_insulin'] as num?)?.toDouble(),
      appliedInsulin: (json['applied_insulin'] as num?)?.toDouble(),
      gptRawResponse: json['gpt_raw_response'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'id': id,
      'user_id': userId,
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'glucose_mgdl': glucoseMgdl,
      'food_text': foodText,
      'food_image_path': foodImagePath,
      'recommended_insulin': recommendedInsulin,
      'applied_insulin': appliedInsulin,
      'gpt_raw_response': gptRawResponse,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'glucose_mgdl': glucoseMgdl,
      'food_text': foodText,
      'recommended_insulin': recommendedInsulin,
      'applied_insulin': appliedInsulin,
    };
  }

  Entry copyWith({
    DateTime? recordedAt,
    int? glucoseMgdl,
    String? foodText,
    double? recommendedInsulin,
    Object? appliedInsulin = _unset,
  }) {
    return Entry(
      id: id,
      userId: userId,
      recordedAt: recordedAt ?? this.recordedAt,
      glucoseMgdl: glucoseMgdl ?? this.glucoseMgdl,
      foodText: foodText ?? this.foodText,
      foodImagePath: foodImagePath,
      recommendedInsulin: recommendedInsulin ?? this.recommendedInsulin,
      appliedInsulin: identical(appliedInsulin, _unset)
          ? this.appliedInsulin
          : appliedInsulin as double?,
      gptRawResponse: gptRawResponse,
      createdAt: createdAt,
    );
  }
}

const Object _unset = Object();

class InsulinRecommendation {
  const InsulinRecommendation({
    required this.carboidratosG,
    required this.correcaoU,
    required this.bolusComidaU,
    required this.insulinaRecomendadaU,
    this.iobU = 0,
    this.observacao,
    this.source = 'ai',
    this.metaMgdl,
    this.metaPeriodo,
    this.horarioBr,
    this.raw,
  });

  final double carboidratosG;
  final double correcaoU;
  final double bolusComidaU;
  final double insulinaRecomendadaU;
  final double iobU;
  final String? observacao;
  final String source;
  final int? metaMgdl;
  final String? metaPeriodo;
  final String? horarioBr;
  final Map<String, dynamic>? raw;

  String? get metaDisplay {
    if (metaMgdl == null) return null;
    final periodo = metaPeriodo ?? '';
    return 'Meta aplicada: $metaMgdl mg/dL${periodo.isEmpty ? '' : ' ($periodo)'}';
  }

  factory InsulinRecommendation.fromJson(Map<String, dynamic> json) {
    return InsulinRecommendation(
      carboidratosG: (json['carboidratos_g'] as num?)?.toDouble() ?? 0,
      correcaoU: (json['correcao_u'] as num?)?.toDouble() ?? 0,
      bolusComidaU: (json['bolus_comida_u'] as num?)?.toDouble() ?? 0,
      insulinaRecomendadaU:
          (json['insulina_recomendada_u'] as num?)?.toDouble() ??
              (json['recommended_insulin'] as num?)?.toDouble() ??
              0,
      iobU: (json['iob_u'] as num?)?.toDouble() ?? 0,
      observacao: json['observacao'] as String?,
      source: (json['source'] as String?) ?? 'ai',
      metaMgdl: (json['meta_mgdl'] as num?)?.toInt(),
      metaPeriodo: json['meta_periodo'] as String?,
      horarioBr: json['horario_br'] as String?,
      raw: json,
    );
  }

  /// Best-effort rebuild from a saved entry (history detail).
  factory InsulinRecommendation.fromEntry(Entry entry) {
    final raw = entry.gptRawResponse;
    if (raw != null && raw.isNotEmpty) {
      try {
        return InsulinRecommendation.fromJson(raw);
      } catch (_) {}
    }
    return InsulinRecommendation(
      carboidratosG: 0,
      correcaoU: 0,
      bolusComidaU: 0,
      insulinaRecomendadaU: entry.recommendedInsulin ?? 0,
      source: 'manual',
      raw: raw,
    );
  }
}
