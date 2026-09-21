import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Profile timezone clock for day/night targets, AI bolus, and clinical UI.
class AppTime {
  AppTime._();

  static const defaultLocationName = 'America/Sao_Paulo';

  /// Curated IANA zones shown in the profile picker.
  static const curatedLocations = <({String id, String label})>[
    (id: 'America/Sao_Paulo', label: 'Brasília (America/Sao_Paulo)'),
    (id: 'America/Fortaleza', label: 'Fortaleza (UTC−3)'),
    (id: 'America/Manaus', label: 'Manaus (UTC−4)'),
    (id: 'America/Cuiaba', label: 'Cuiabá (America/Cuiaba)'),
    (id: 'America/Rio_Branco', label: 'Rio Branco (UTC−5)'),
    (id: 'America/Noronha', label: 'Fernando de Noronha'),
    (id: 'America/New_York', label: 'Nova York'),
    (id: 'Europe/Lisbon', label: 'Lisboa'),
    (id: 'Europe/London', label: 'Londres'),
    (id: 'UTC', label: 'UTC'),
  ];

  static bool _initialized = false;
  static String _locationName = defaultLocationName;

  static void ensureInitialized() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static String get locationName => _locationName;

  static String labelFor(String iana) {
    for (final e in curatedLocations) {
      if (e.id == iana) return e.label;
    }
    return iana;
  }

  /// Sets the active IANA zone. Invalid names fall back to [defaultLocationName].
  static void setLocation(String iana) {
    ensureInitialized();
    final name = iana.trim().isEmpty ? defaultLocationName : iana.trim();
    try {
      tz.getLocation(name);
      _locationName = name;
    } catch (_) {
      _locationName = defaultLocationName;
    }
  }

  static tz.Location get location {
    ensureInitialized();
    return tz.getLocation(_locationName);
  }

  static tz.TZDateTime now() {
    ensureInitialized();
    return tz.TZDateTime.now(location);
  }

  static tz.TZDateTime fromUtc(DateTime instant) {
    ensureInitialized();
    return tz.TZDateTime.from(instant.toUtc(), location);
  }

  static String formatHm([tz.TZDateTime? when]) {
    final t = when ?? now();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static int minuteOfDay(tz.TZDateTime when) => when.hour * 60 + when.minute;

  /// Formats an absolute instant in the profile timezone.
  static String formatDateTime(DateTime instant) {
    final t = fromUtc(instant);
    final d = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    final y = t.year.toString();
    return '$d/$mo/$y ${formatHm(t)}';
  }

  static String formatDateShort(DateTime instant) {
    final t = fromUtc(instant);
    final d = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    return '$d/$mo';
  }

  static String formatDateTimeShort(DateTime instant) {
    final t = fromUtc(instant);
    return '${formatDateShort(instant)} ${formatHm(t)}';
  }
}
