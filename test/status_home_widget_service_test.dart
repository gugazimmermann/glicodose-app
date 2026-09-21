import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/models/libre_glucose.dart';
import 'package:diabetes_app/services/status_home_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('home_widget');
  final stored = <String, Object?>{};

  setUp(() {
    stored.clear();
    StatusHomeWidgetService.supportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'saveWidgetData':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          stored[args['id'] as String] = args['data'];
          return true;
        case 'getWidgetData':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          return stored[args['id'] as String];
        case 'updateWidget':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    StatusHomeWidgetService.supportedOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('publish writes glucose and iob keys', () async {
    await StatusHomeWidgetService.publish(
      libreConnected: true,
      reading: LibreGlucoseReading(
        glucoseMgdl: 128,
        recordedAt: DateTime.now(),
        trend: 3,
      ),
      iobU: 3,
      syncing: false,
      clearError: true,
    );
    expect(stored[StatusHomeWidgetService.keyLibreConnected], isTrue);
    expect(stored[StatusHomeWidgetService.keyHasGlucose], isTrue);
    expect(stored[StatusHomeWidgetService.keyGlucoseMgdl], 128);
    expect(stored[StatusHomeWidgetService.keyIobU], 3);
    expect(stored[StatusHomeWidgetService.keyUpdatedAt], isNotNull);
  });

  test('publish clearGlucose clears reading keys', () async {
    await StatusHomeWidgetService.publish(
      reading: LibreGlucoseReading(glucoseMgdl: 100, recordedAt: DateTime.now()),
    );
    await StatusHomeWidgetService.publish(clearGlucose: true, iobU: 0);
    expect(stored[StatusHomeWidgetService.keyHasGlucose], isFalse);
    expect(stored[StatusHomeWidgetService.keyGlucoseMgdl], isNull);
  });

  test('clear resets widget state', () async {
    await StatusHomeWidgetService.publish(
      libreConnected: true,
      reading: LibreGlucoseReading(glucoseMgdl: 140, recordedAt: DateTime.now()),
      iobU: 2,
      lastError: 'x',
    );
    await StatusHomeWidgetService.clear();
    expect(stored[StatusHomeWidgetService.keyLibreConnected], isFalse);
    expect(stored[StatusHomeWidgetService.keyHasGlucose], isFalse);
    expect(stored[StatusHomeWidgetService.keyIobU], 0);
    expect(stored[StatusHomeWidgetService.keySyncing], isFalse);
  });

  test('publishIobTick updates iob', () async {
    await StatusHomeWidgetService.publish(
      reading: LibreGlucoseReading(
        glucoseMgdl: 120,
        recordedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );
    await StatusHomeWidgetService.publishIobTick(4);
    expect(stored[StatusHomeWidgetService.keyIobU], 4);
  });

  test('isLibreConnected reads stored flag', () async {
    await StatusHomeWidgetService.publish(libreConnected: true);
    expect(await StatusHomeWidgetService.isLibreConnected(), isTrue);
  });

  test('unsupported override skips publish', () async {
    StatusHomeWidgetService.supportedOverride = false;
    stored.clear();
    await StatusHomeWidgetService.publish(iobU: 9);
    expect(stored, isEmpty);
  });
}
