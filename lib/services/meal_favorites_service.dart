import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class MealFavorite {
  const MealFavorite({
    required this.text,
    this.carbsG,
  });

  final String text;
  final double? carbsG;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (carbsG != null) 'carbs_g': carbsG,
      };

  factory MealFavorite.fromJson(Map<String, dynamic> json) {
    return MealFavorite(
      text: (json['text'] as String?)?.trim() ?? '',
      carbsG: (json['carbs_g'] as num?)?.toDouble(),
    );
  }
}

/// Local favorites for quick re-entry of common meals.
class MealFavoritesService {
  MealFavoritesService();

  static const _prefsKey = 'meal_favorites_v1';
  static const maxFavorites = 12;

  Future<List<MealFavorite>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    return raw
        .map((e) {
          try {
            return MealFavorite.fromJson(
              Map<String, dynamic>.from(jsonDecode(e) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<MealFavorite>()
        .where((f) => f.text.isNotEmpty)
        .toList();
  }

  Future<void> add(MealFavorite favorite) async {
    final text = favorite.text.trim();
    if (text.isEmpty) return;
    final current = await list();
    final next = [
      MealFavorite(text: text, carbsG: favorite.carbsG),
      ...current.where((f) => f.text.toLowerCase() != text.toLowerCase()),
    ].take(maxFavorites).toList();
    await _save(next);
  }

  Future<void> remove(String text) async {
    final current = await list();
    final next = current
        .where((f) => f.text.toLowerCase() != text.trim().toLowerCase())
        .toList();
    await _save(next);
  }

  Future<void> _save(List<MealFavorite> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      favorites.map((f) => jsonEncode(f.toJson())).toList(),
    );
  }
}
