import 'package:flutter/services.dart';

/// Allows digits plus `,` / `.` for Brazilian decimal input.
final decimalInputFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'[0-9.,]'),
);

double? parseDecimal(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}
