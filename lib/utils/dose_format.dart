/// Formats and rounds insulin / carbohydrate quantities as whole numbers.
int asWhole(num value) => value.round();

/// Like [asWhole] but never negative (doses).
int asWholeDose(num value) {
  final n = value.round();
  return n < 0 ? 0 : n;
}

String formatWhole(num? value) {
  if (value == null) return '—';
  return '${asWhole(value)}';
}
