import 'package:diabetes_app/models/entry.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/bolus_calculator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InsulinService {
  InsulinService(this._client, {BolusCalculator? calculator})
      : _calculator = calculator ?? const BolusCalculator();

  final SupabaseClient _client;
  final BolusCalculator _calculator;

  /// AI estimates carbs only; server applies the clinical formula.
  Future<InsulinRecommendation> recommendWithAi({
    required int glucoseMgdl,
    required String localTime,
    required String timezone,
    double iobU = 0,
    String? foodText,
    String? foodImageUrl,
  }) async {
    final response = await _client.functions.invoke(
      'recommend-insulin',
      body: {
        'glucose_mgdl': glucoseMgdl,
        'local_time': localTime,
        'timezone': timezone,
        'iob_u': iobU,
        'food_text': foodText,
        'food_image_url': foodImageUrl,
      },
    );

    if (response.status != 200) {
      final error = response.data;
      final message = error is Map && error['error'] != null
          ? error['error'].toString()
          : 'Falha ao estimar carboidratos (${response.status})';
      throw Exception(message);
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    data['source'] = data['source'] ?? 'ai';
    return InsulinRecommendation.fromJson(data);
  }

  /// Fully local: user-provided carbs + profile formula (no OpenAI).
  InsulinRecommendation calculateManual({
    required int glucoseMgdl,
    required double carboidratosG,
    required Profile profile,
    double iobU = 0,
    String? observacao,
  }) {
    return _calculator.calculate(
      glucoseMgdl: glucoseMgdl,
      carboidratosG: carboidratosG,
      profile: profile,
      iobU: iobU,
      observacao: observacao ?? 'Cálculo local com carboidratos informados.',
      source: 'manual',
    );
  }
}
