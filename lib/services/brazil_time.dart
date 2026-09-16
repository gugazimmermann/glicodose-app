import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Official Brazilian time used for day/night glucose targets.
class BrazilTime {
  BrazilTime._();

  static const locationName = 'America/Sao_Paulo';
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static tz.Location get location {
    ensureInitialized();
    return tz.getLocation(locationName);
  }

  static tz.TZDateTime now() {
    ensureInitialized();
    return tz.TZDateTime.now(location);
  }

  static String formatHm([tz.TZDateTime? when]) {
    final t = when ?? now();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static int minuteOfDay(tz.TZDateTime when) => when.hour * 60 + when.minute;
}
