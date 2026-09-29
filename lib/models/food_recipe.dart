class FoodRecipe {
  const FoodRecipe({
    required this.id,
    required this.userId,
    required this.name,
    required this.note,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FoodRecipe.fromJson(Map<String, dynamic> json) {
    return FoodRecipe(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: (json['name'] as String?)?.trim() ?? '',
      note: (json['note'] as String?)?.trim() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }
}

/// Lines sent to the carb model. Empty name or note is skipped.
String formatRecipeAdjustments(Iterable<FoodRecipe> recipes) {
  final parts = <String>[];
  for (final recipe in recipes) {
    final name = recipe.name.trim();
    final note = recipe.note.trim();
    if (name.isEmpty || note.isEmpty) continue;
    parts.add('$name — $note');
  }
  if (parts.isEmpty) return '';
  return 'Ajustes do paciente, com prioridade sobre o item TACO '
      'correspondente: ${parts.join('; ')}.';
}
