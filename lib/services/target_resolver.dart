import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/brazil_time.dart';
import 'package:timezone/timezone.dart' as tz;

class EffectiveTarget {
  const EffectiveTarget({
    required this.mgdl,
    required this.isNight,
    required this.minuteOfDay,
    required this.timeLabel,
  });

  final int mgdl;
  final bool isNight;
  final int minuteOfDay;
  final String timeLabel;

  String get periodLabel => isNight ? 'noite' : 'dia';

  String get displayLabel => 'Meta aplicada: $mgdl mg/dL ($periodLabel)';
}

class TargetResolver {
  const TargetResolver();

  /// Night window may cross midnight (e.g. 20:00–05:59).
  bool isNightWindow({
    required int minuteOfDay,
    required int nightStartMinute,
    required int nightEndMinute,
  }) {
    if (nightStartMinute == nightEndMinute) return false;
    if (nightStartMinute < nightEndMinute) {
      // Same-day window (unusual): e.g. 01:00–05:00
      return minuteOfDay >= nightStartMinute && minuteOfDay <= nightEndMinute;
    }
    // Crosses midnight: [start, 24h) U [0, end]
    return minuteOfDay >= nightStartMinute || minuteOfDay <= nightEndMinute;
  }

  EffectiveTarget resolve(Profile profile, {tz.TZDateTime? nowBr}) {
    final when = nowBr ?? BrazilTime.now();
    final minute = BrazilTime.minuteOfDay(when);
    final night = isNightWindow(
      minuteOfDay: minute,
      nightStartMinute: profile.nightStartMinute,
      nightEndMinute: profile.nightEndMinute,
    );
    final dayTarget = profile.targetGlucoseMgdl ?? 110;
    final nightTarget = profile.targetNightMgdl ?? dayTarget;
    return EffectiveTarget(
      mgdl: night ? nightTarget : dayTarget,
      isNight: night,
      minuteOfDay: minute,
      timeLabel: BrazilTime.formatHm(when),
    );
  }
}
