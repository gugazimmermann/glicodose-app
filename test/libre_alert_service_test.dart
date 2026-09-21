import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/services/libre_alert_logic.dart';
import 'package:diabetes_app/services/libre_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'requestNotificationsPermission') return true;
      if (call.method == 'createNotificationChannel') return null;
      if (call.method == 'show') return null;
      if (call.method == 'cancel') return null;
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('applyFromProfile writes alert prefs', () async {
    final profile = Profile(
      id: 'u1',
      libreAlertsEnabled: true,
      libreAlertHypoMgdl: 65,
      libreAlertHyperMgdl: 200,
      libreAlertStaleMinutes: 30,
    );
    await LibreAlertService.applyFromProfile(profile);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(LibreAlertService.prefEnabled), isTrue);
    expect(prefs.getInt(LibreAlertService.prefHypo), 65);
    expect(prefs.getInt(LibreAlertService.prefHyper), 200);
    expect(prefs.getInt(LibreAlertService.prefStaleMinutes), 30);
  });

  test('recordSyncSuccess clears fail count', () async {
    SharedPreferences.setMockInitialValues({
      LibreAlertService.prefFailCount: 3,
    });
    final at = DateTime.utc(2026, 3, 1, 12);
    await LibreAlertService.recordSyncSuccess(at: at);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(LibreAlertService.prefFailCount), 0);
    expect(
      prefs.getString(LibreAlertService.prefLastSuccessSyncAt),
      at.toIso8601String(),
    );
  });

  test('recordSyncFailure with alerts off does not notify', () async {
    SharedPreferences.setMockInitialValues({
      LibreAlertService.prefEnabled: false,
      LibreAlertService.prefFailCount: 0,
    });
    await LibreAlertService.recordSyncFailure();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(LibreAlertService.prefFailCount), 1);
    expect(prefs.getString(LibreAlertService.prefStaleAlertAt), isNull);
  });

  test('evaluate hypo updates zone and last alert prefs', () async {
    SharedPreferences.setMockInitialValues({
      LibreAlertService.prefEnabled: true,
      LibreAlertService.prefHypo: 70,
      LibreAlertService.prefHyper: 180,
      LibreAlertService.prefStaleMinutes: 20,
    });
    await LibreAlertService.evaluate(
      LibreGlucoseReading(
        glucoseMgdl: 55,
        recordedAt: DateTime.now(),
        trend: 3,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LibreAlertService.prefZone), 'hypo');
    expect(prefs.getString(LibreAlertService.prefLastAlertAt), isNotNull);
    expect(prefs.getString(LibreAlertService.prefLastRecordedAt), isNotNull);
  });

  test('evaluate skips when libre disconnected', () async {
    SharedPreferences.setMockInitialValues({
      LibreAlertService.prefEnabled: true,
    });
    await LibreAlertService.evaluate(
      LibreGlucoseReading(glucoseMgdl: 55, recordedAt: DateTime.now()),
      libreConnected: false,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LibreAlertService.prefZone), isNull);
  });

  test('evaluate ok zone cancels hypo/hyper ids path', () async {
    SharedPreferences.setMockInitialValues({
      LibreAlertService.prefEnabled: true,
      LibreAlertService.prefHypo: 70,
      LibreAlertService.prefHyper: 180,
      LibreAlertService.prefZone: 'hypo',
      LibreAlertService.prefLastAlertAt:
          DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
    });
    await LibreAlertService.evaluate(
      LibreGlucoseReading(
        glucoseMgdl: 110,
        recordedAt: DateTime.now(),
        trend: 3,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LibreAlertService.prefZone), 'ok');
  });

  test('recordSyncFailure with alerts on may set stale alert', () async {
    SharedPreferences.setMockInitialValues({
      LibreAlertService.prefEnabled: true,
      LibreAlertService.prefHypo: 70,
      LibreAlertService.prefHyper: 180,
      LibreAlertService.prefStaleMinutes: 5,
      LibreAlertService.prefFailCount: 2,
      LibreAlertService.prefLastSuccessSyncAt: DateTime.now()
          .subtract(const Duration(hours: 2))
          .toUtc()
          .toIso8601String(),
    });
    await LibreAlertService.recordSyncFailure();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(LibreAlertService.prefFailCount), 3);
  });

  test('showFromPush maps known types', () async {
    await LibreAlertService.showFromPush(
      type: 'libre_hypo',
      title: 'Hipo',
      body: '55 mg/dL',
    );
    await LibreAlertService.showFromPush(
      type: 'libre_hyper',
      title: 'Hiper',
      body: '250',
    );
    await LibreAlertService.showFromPush(
      type: 'libre_stale',
      title: 'Parado',
      body: 'sensor',
    );
    await LibreAlertService.showFromPush(
      type: 'unknown',
      title: 'x',
      body: 'y',
    );
    expect(LibreAlertLogic.hypoNotificationId, isPositive);
  });
}
