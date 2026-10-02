import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Joins a recognized food phrase into the meal field.
/// An empty field is replaced. Existing text stays, and the new words follow.
String mergeFoodText(String current, String added) {
  final extra = added.trim();
  if (extra.isEmpty) return current;
  final base = current.trim();
  return base.isEmpty ? extra : '$base $extra';
}

/// Rejects empty or oversized photos before they are sent for description.
void ensureFoodPhotoBytes(Uint8List bytes) {
  if (bytes.length < 64) {
    throw Exception('Foto inválida.');
  }
  if (bytes.length > 4 * 1024 * 1024) {
    throw Exception('Foto muito grande.');
  }
}

/// MIME type for a photo chosen by the camera or gallery picker.
String foodPhotoMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

class FoodPhotoService {
  FoodPhotoService(this._client);

  final SupabaseClient _client;

  /// Sends a compressed food photo and returns a short Portuguese description.
  Future<String> describe(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    ensureFoodPhotoBytes(bytes);

    final response = await _client.functions.invoke(
      'describe-food',
      body: {'image_base64': base64Encode(bytes), 'mime_type': mimeType},
    );

    if (response.status != 200) {
      final error = response.data;
      final message = error is Map && error['error'] != null
          ? error['error'].toString()
          : 'Falha ao descrever a foto (${response.status})';
      throw Exception(message);
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    final text = (data['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      throw Exception('Não foi possível descrever a foto.');
    }
    return text;
  }
}
