import 'package:diabetes_app/models/food_recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/models/entry.dart';

void main() {
  test('recipe lines skip a blank name or note', () {
    const recipes = [
      FoodRecipe(id: '1', userId: 'u', name: '  ', note: 'leva mais óleo'),
      FoodRecipe(id: '2', userId: 'u', name: 'Arroz', note: '   '),
      FoodRecipe(
        id: '3',
        userId: 'u',
        name: 'Arroz da minha mãe',
        note: 'leva mais óleo',
      ),
      FoodRecipe(id: '4', userId: 'u', name: 'Feijão', note: 'mais caldo'),
    ];

    expect(
      formatRecipeAdjustments(recipes),
      'Ajustes do paciente, com prioridade sobre o item TACO correspondente: '
      'Arroz da minha mãe — leva mais óleo; Feijão — mais caldo.',
    );
    expect(
      formatRecipeAdjustments(const [
        FoodRecipe(id: '1', userId: 'u', name: '', note: ''),
      ]),
      isEmpty,
    );
  });

  test('peso_g is read from the recommendation and absence is null', () {
    final withWeight = InsulinRecommendation.fromJson({
      'carboidratos_g': 40,
      'peso_g': 180,
      'correcao_u': 1,
      'bolus_comida_u': 4,
      'insulina_recomendada_u': 5,
    });
    expect(withWeight.pesoG, 180);

    const without = InsulinRecommendation(
      carboidratosG: 40,
      correcaoU: 1,
      bolusComidaU: 4,
      insulinaRecomendadaU: 5,
    );
    expect(without.pesoG, isNull);
    expect(
      InsulinRecommendation.fromJson({
        'carboidratos_g': 10,
        'peso_g': 0,
        'correcao_u': 0,
        'bolus_comida_u': 1,
        'insulina_recomendada_u': 1,
      }).pesoG,
      isNull,
    );
  });
}
