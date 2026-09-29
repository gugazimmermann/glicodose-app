import 'package:diabetes_app/models/food_recipe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FoodRecipeService {
  FoodRecipeService(this._client);

  final SupabaseClient _client;

  Future<List<FoodRecipe>> list() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client
        .from('food_recipes')
        .select('id, user_id, name, note, created_at, updated_at')
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return [
      for (final raw in rows as List)
        FoodRecipe.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  Future<FoodRecipe> create({
    required String name,
    required String note,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sessão expirada.');
    }
    final row = await _client
        .from('food_recipes')
        .insert({'user_id': userId, 'name': name.trim(), 'note': note.trim()})
        .select('id, user_id, name, note, created_at, updated_at')
        .single();
    return FoodRecipe.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FoodRecipe> update({
    required String id,
    required String name,
    required String note,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sessão expirada.');
    }
    final row = await _client
        .from('food_recipes')
        .update({
          'name': name.trim(),
          'note': note.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', userId)
        .select('id, user_id, name, note, created_at, updated_at')
        .single();
    return FoodRecipe.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> delete(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('food_recipes')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }
}
