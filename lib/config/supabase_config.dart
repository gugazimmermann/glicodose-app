/// Loaded at compile time via --dart-define / --dart-define-from-file.
///
/// Recommended (file `.env` in the project root):
/// ```
/// SUPABASE_URL=https://xxxx.supabase.co
/// SUPABASE_ANON_KEY=eyJ...
/// ```
/// Then: `flutter run --dart-define-from-file=.env`
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR_PROJECT.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );

  static bool get isConfigured =>
      !url.contains('YOUR_PROJECT') && !anonKey.contains('YOUR_SUPABASE');
}
