import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/config/supabase_config.dart';

void main() {
  test('SupabaseConfig exposes dart-define keys', () {
    expect(SupabaseConfig.url, isNotEmpty);
    expect(SupabaseConfig.anonKey, isNotEmpty);
  });
}
