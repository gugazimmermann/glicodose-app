import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Posts a high/low glucose notification with the Android Auto heads-up extender.
///
/// Registered as a plugin so the foreground-service isolate and the FCM
/// background isolate can call it. A channel on MainActivity would not.
class GlicoDoseCarAlerts {
  static const channelName = 'app.glicodose/car_alerts';
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    required String zone,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('show', {
      'id': id,
      'title': title,
      'body': body,
      'zone': zone,
    });
  }
}
