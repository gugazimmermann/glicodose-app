/// Formats and rounds insulin / carbohydrate quantities as whole numbers.
int asWhole(num value) {
  if (value.isNaN || value.isInfinite) return 0;
  return value.round();
}

/// Like [asWhole] but never negative (doses).
int asWholeDose(num value) {
  if (value.isNaN || value.isInfinite) return 0;
  final n = value.round();
  return n < 0 ? 0 : n;
}

String formatWhole(num? value) {
  if (value == null || value.isNaN || value.isInfinite) return '—';
  return '${asWhole(value)}';
}
