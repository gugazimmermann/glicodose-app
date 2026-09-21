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
    this.glucoseSource,
    this.healthGlucoseUuid,
    this.healthInsulinUuid,
    this.healthMealClientId,
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
  /// manual | health | libre
  final String? glucoseSource;
  final String? healthGlucoseUuid;
  final String? healthInsulinUuid;
  final String? healthMealClientId;
  final DateTime? createdAt;

  factory Entry.fromJson(Map<String, dynamic> json) {
    final rawGpt = json['gpt_raw_response'];
    return Entry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      glucoseMgdl: (json['glucose_mgdl'] as num).round(),
      foodText: json['food_text'] as String?,
      foodImagePath: json['food_image_path'] as String?,
      recommendedInsulin: (json['recommended_insulin'] as num?)?.toDouble(),
      appliedInsulin: (json['applied_insulin'] as num?)?.toDouble(),
      gptRawResponse: rawGpt == null
          ? null
          : Map<String, dynamic>.from(rawGpt as Map),
      glucoseSource: json['glucose_source'] as String?,
      healthGlucoseUuid: json['health_glucose_uuid'] as String?,
      healthInsulinUuid: json['health_insulin_uuid'] as String?,
      healthMealClientId: json['health_meal_client_id'] as String?,
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
      'glucose_source': glucoseSource,
      'health_glucose_uuid': healthGlucoseUuid,
      'health_insulin_uuid': healthInsulinUuid,
      'health_meal_client_id': healthMealClientId,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'glucose_mgdl': glucoseMgdl,
      'food_text': foodText,
      'recommended_insulin': recommendedInsulin,
      'applied_insulin': appliedInsulin,
      if (gptRawResponse != null) 'gpt_raw_response': gptRawResponse,
      'glucose_source': glucoseSource,
      'health_glucose_uuid': healthGlucoseUuid,
      'health_insulin_uuid': healthInsulinUuid,
      'health_meal_client_id': healthMealClientId,
    };
  }

  Entry copyWith({
    DateTime? recordedAt,
    int? glucoseMgdl,
    String? foodText,
    double? recommendedInsulin,
    Object? appliedInsulin = _unset,
    Object? gptRawResponse = _unset,
    Object? glucoseSource = _unset,
    Object? healthGlucoseUuid = _unset,
    Object? healthInsulinUuid = _unset,
    Object? healthMealClientId = _unset,
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
      gptRawResponse: identical(gptRawResponse, _unset)
          ? this.gptRawResponse
          : gptRawResponse as Map<String, dynamic>?,
      glucoseSource: identical(glucoseSource, _unset)
          ? this.glucoseSource
          : glucoseSource as String?,
      healthGlucoseUuid: identical(healthGlucoseUuid, _unset)
          ? this.healthGlucoseUuid
          : healthGlucoseUuid as String?,
      healthInsulinUuid: identical(healthInsulinUuid, _unset)
          ? this.healthInsulinUuid
          : healthInsulinUuid as String?,
      healthMealClientId: identical(healthMealClientId, _unset)
          ? this.healthMealClientId
          : healthMealClientId as String?,
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
    this.confianca,
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
  /// AI carb confidence: baixa | media | alta
  final String? confianca;
  final Map<String, dynamic>? raw;

  String? get metaDisplay {
    if (metaMgdl == null) return null;
    final periodo = metaPeriodo ?? '';
    return 'Meta aplicada: $metaMgdl mg/dL${periodo.isEmpty ? '' : ' ($periodo)'}';
  }

  String get confiancaLabel {
    switch (confianca) {
      case 'baixa':
        return 'Baixa';
      case 'alta':
        return 'Alta';
      case 'media':
        return 'Média';
      default:
        return '—';
    }
  }

  factory InsulinRecommendation.fromJson(Map<String, dynamic> json) {
    return InsulinRecommendation(
      carboidratosG: _finite(json['carboidratos_g']),
      correcaoU: _finite(json['correcao_u']),
      bolusComidaU: _finite(json['bolus_comida_u']),
      insulinaRecomendadaU: _finite(
        json['insulina_recomendada_u'] ?? json['recommended_insulin'],
      ),
      iobU: _finite(json['iob_u']),
      observacao: json['observacao'] as String?,
      source: (json['source'] as String?) ?? 'ai',
      metaMgdl: (json['meta_mgdl'] as num?)?.toInt(),
      metaPeriodo: json['meta_periodo'] as String?,
      horarioBr: json['horario_br'] as String?,
      confianca: json['confianca'] as String?,
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
      insulinaRecomendadaU: _finite(entry.recommendedInsulin),
      source: 'manual',
      raw: raw,
    );
  }

  InsulinRecommendation copyWith({
    double? carboidratosG,
    double? correcaoU,
    double? bolusComidaU,
    double? insulinaRecomendadaU,
    double? iobU,
    String? observacao,
    String? source,
    int? metaMgdl,
    String? metaPeriodo,
    String? horarioBr,
    String? confianca,
    Map<String, dynamic>? raw,
  }) {
    return InsulinRecommendation(
      carboidratosG: carboidratosG ?? this.carboidratosG,
      correcaoU: correcaoU ?? this.correcaoU,
      bolusComidaU: bolusComidaU ?? this.bolusComidaU,
      insulinaRecomendadaU:
          insulinaRecomendadaU ?? this.insulinaRecomendadaU,
      iobU: iobU ?? this.iobU,
      observacao: observacao ?? this.observacao,
      source: source ?? this.source,
      metaMgdl: metaMgdl ?? this.metaMgdl,
      metaPeriodo: metaPeriodo ?? this.metaPeriodo,
      horarioBr: horarioBr ?? this.horarioBr,
      confianca: confianca ?? this.confianca,
      raw: raw ?? this.raw,
    );
  }
}

double _finite(Object? value, [double fallback = 0]) {
  if (value is! num) return fallback;
  final d = value.toDouble();
  if (d.isNaN || d.isInfinite) return fallback;
  return d;
}
