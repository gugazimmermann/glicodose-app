import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/iob_background.dart';
import 'package:diabetes_app/services/iob_badge_service.dart';
import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Owns live IOB state: network refresh, 1-minute local ticks, badge sync,
/// and Android background scheduling.
class IobLiveController {
  IobLiveController({
    required EntryService entries,
    required ProfileService profile,
    required IobBadgeService badge,
  })  : _entries = entries,
        _profile = profile,
        _badge = badge;

  final EntryService _entries;
  final ProfileService _profile;
  final IobBadgeService _badge;
  final IobService _iob = const IobService();

  final ValueNotifier<IobSnapshot> snapshot =
      ValueNotifier<IobSnapshot>(IobSnapshot.empty);

  /// True while the first / active network refresh is in flight.
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// True if the last network refresh failed and we have no usable cache.
  final ValueNotifier<bool> failed = ValueNotifier<bool>(false);

  Timer? _timer;
  bool _started = false;
  List<IobCachedDose> _doses = const [];
  double _durationHours = 4.0;

  /// Start periodic local recompute (call on login).
  void start() {
    if (_started) return;
    _started = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(tick());
    });
  }

  /// Stop timer and clear UI state (call on logout). Does not clear badge
  /// by itself — callers should also [clear].
  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> clear() async {
    stop();
    _doses = const [];
    _durationHours = 4.0;
    snapshot.value = IobSnapshot.empty;
    failed.value = false;
    loading.value = false;
    await IobCache.clear();
    await IobBackground.cancel();
    await _badge.clear();
  }

  /// Fetch profile + recent entries, persist cache, update UI + badge.
  Future<void> refreshFromNetwork() async {
    loading.value = true;
    failed.value = false;
    try {
      await _badge.ensureReady();
      final profile = await _profile.fetchCurrent();
      final duration = profile?.insulinDurationHours ?? 4.0;
      _durationHours = duration;

      if (duration <= 0) {
        _doses = const [];
        await _publish(IobSnapshot.empty);
        await IobCache.clear();
        await IobBackground.cancel();
        return;
      }

      final since =
          DateTime.now().subtract(Duration(hours: duration.ceil() + 1));
      final entries = await _entries.listEntriesSince(since);
      _doses = IobCache.fromEntries(entries);
      final snap = _iob.computeIob(
        recentEntries: entries,
        durationHours: duration,
        now: DateTime.now(),
      );
      await IobCache.save(doses: _doses, durationHours: duration);
      await _publish(snap);
      await _syncBackgroundSchedule(snap);
    } catch (_) {
      // Fall back to local cache if network fails.
      final cached = await IobCache.load();
      if (cached != null) {
        _doses = cached.doses;
        _durationHours = cached.durationHours;
        final snap = IobCache.compute(
          doses: _doses,
          durationHours: _durationHours,
          now: DateTime.now(),
        );
        await _publish(snap);
        failed.value = false;
      } else {
        failed.value = true;
        snapshot.value = IobSnapshot.empty;
      }
    } finally {
      loading.value = false;
    }
  }

  /// Recompute from in-memory cache (or prefs) without network.
  Future<void> tick() async {
    if (_doses.isEmpty && _durationHours > 0) {
      final cached = await IobCache.load();
      if (cached != null) {
        _doses = cached.doses;
        _durationHours = cached.durationHours;
      }
    }
    final snap = IobCache.compute(
      doses: _doses,
      durationHours: _durationHours,
      now: DateTime.now(),
    );
    await _publish(snap);
    await _syncBackgroundSchedule(snap);
  }

  Future<void> _publish(IobSnapshot snap) async {
    snapshot.value = snap;
    final n = asWholeDose(snap.iobU);
    await _badge.applyCount(n > 0 ? n : 0);
  }

  Future<void> _syncBackgroundSchedule(IobSnapshot snap) async {
    if (asWholeDose(snap.iobU) > 0) {
      await IobBackground.ensureScheduled();
    } else {
      await IobBackground.cancel();
    }
  }

  void dispose() {
    stop();
    snapshot.dispose();
    loading.dispose();
    failed.dispose();
  }
}
