import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Keeps the launcher icon badge in sync with active rapid insulin (IOB).
class IobBadgeService {
  IobBadgeService({
    required EntryService entries,
    required ProfileService profile,
  })  : _entries = entries,
        _profile = profile;

  final EntryService _entries;
  final ProfileService _profile;
  final IobService _iob = const IobService();

  bool _notificationAsked = false;

  Future<void> ensureNotificationPermission() async {
    if (_notificationAsked) return;
    _notificationAsked = true;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied || status.isRestricted) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Non-blocking: badge may still work on some launchers.
    }
  }

  Future<void> refresh() async {
    try {
      if (!await AppBadgePlus.isSupported()) return;

      final profile = await _profile.fetchCurrent();
      final duration = profile?.insulinDurationHours ?? 4.0;
      if (duration <= 0) {
        await AppBadgePlus.updateBadge(0);
        return;
      }

      final since =
          DateTime.now().subtract(Duration(hours: duration.ceil() + 1));
      final entries = await _entries.listEntriesSince(since);
      final snap = _iob.computeIob(
        recentEntries: entries,
        durationHours: duration,
        now: DateTime.now(),
      );
      final n = asWholeDose(snap.iobU);
      await AppBadgePlus.updateBadge(n > 0 ? n : 0);
    } catch (_) {
      // Ignore badge failures (unsupported launcher, offline, etc.).
    }
  }

  Future<void> clear() async {
    try {
      await AppBadgePlus.updateBadge(0);
    } catch (_) {}
  }
}
