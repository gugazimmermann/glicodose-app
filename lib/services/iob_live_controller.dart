import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/iob_background.dart';
import 'package:diabetes_app/services/iob_badge_service.dart';
import 'package:diabetes_app/services/iob_cache.dart';
import 'package:diabetes_app/services/iob_foreground_task.dart';
import 'package:diabetes_app/services/iob_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';
import 'package:diabetes_app/utils/dose_format.dart';

/// Owns live IOB state: network refresh, 1-minute local ticks, badge sync,
/// Android foreground service, and Workmanager fallback.
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
  bool _listeningTaskData = false;
  List<IobCachedDose> _doses = const [];
  double _durationHours = 4.0;

  /// Start periodic local recompute (call on login). Always rearms the timer.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(tick());
    });
    _ensureTaskDataListener();
  }

  void _ensureTaskDataListener() {
    if (_listeningTaskData || kIsWeb) return;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _listeningTaskData = true;
  }

  void _removeTaskDataListener() {
    if (!_listeningTaskData) return;
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _listeningTaskData = false;
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    final raw = data[IobForegroundTask.dataKeyIobU];
    if (raw is! num) return;
    final n = asWholeDose(raw);
    // Recompute full snapshot from cache so contributions stay accurate.
    unawaited(() async {
      final snap = await IobCache.recompute();
      snapshot.value = snap;
      if (n <= 0) {
        await _badge.applyCount(0);
        await IobBackground.cancel();
      }
    }());
  }

  /// Stop timer (call on logout / detached). Does not clear badge by itself.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> clear() async {
    stop();
    _removeTaskDataListener();
    _doses = const [];
    _durationHours = 4.0;
    snapshot.value = IobSnapshot.empty;
    failed.value = false;
    loading.value = false;
    await IobCache.clear();
    await IobBackground.cancel();
    await IobForegroundTask.stop();
    await _badge.clear();
    await StatusHomeWidgetService.clear();
  }

  /// Fetch profile + recent entries, persist cache, update UI + badge + FGS.
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
    } catch (e, st) {
      debugPrint('IobLiveController.refreshFromNetwork failed: $e\n$st');
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
  }

  Future<void> _publish(IobSnapshot snap) async {
    snapshot.value = snap;
    final n = asWholeDose(snap.iobU);
    unawaited(StatusHomeWidgetService.publishIobTick(n));
    if (n > 0) {
      final fgsOk = await IobForegroundTask.ensureRunning(n);
      // When FGS is up it owns the status notification (with showBadge).
      // If FGS failed to start, fall back to the local ongoing notification
      // so the launcher still gets a badge/dot via Notification.number.
      await _badge.applyCount(n, skipNotification: fgsOk);
      await IobBackground.ensureScheduled();
    } else {
      await IobForegroundTask.stop();
      await _badge.applyCount(0);
      await IobBackground.cancel();
    }
  }

  void dispose() {
    stop();
    _removeTaskDataListener();
    snapshot.dispose();
    loading.dispose();
    failed.dispose();
  }
}
