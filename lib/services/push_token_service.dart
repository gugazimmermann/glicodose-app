import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/services/libre_alert_service.dart';

import 'package:diabetes_app/firebase_options.dart';

/// Registers FCM tokens in `device_tokens` when Firebase is configured.
class PushTokenService {
  PushTokenService(this._client);

  final SupabaseClient _client;
  StreamSubscription<String>? _tokenSub;
  static bool _firebaseReady = false;
  static bool _firebaseChecked = false;
  static bool _listenersAttached = false;

  static Future<bool> ensureFirebase() async {
    if (kIsWeb) return false;
    if (_firebaseChecked) return _firebaseReady;
    _firebaseChecked = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseReady = true;
    } catch (e, st) {
      debugPrint('Firebase not available (push disabled): $e\n$st');
      _firebaseReady = false;
    }
    return _firebaseReady;
  }

  /// Call once after login. No-ops if Firebase / google-services are missing.
  Future<void> register() async {
    if (!await ensureFirebase()) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (!_listenersAttached) {
        _listenersAttached = true;
        FirebaseMessaging.onMessage.listen(_onForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
      }

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _onMessageOpened(initial);
      }

      final token = await messaging.getToken();
      if (token != null) {
        await _upsertToken(token);
      }
      await _tokenSub?.cancel();
      _tokenSub = messaging.onTokenRefresh.listen(_upsertToken);
    } catch (e, st) {
      debugPrint('PushTokenService.register failed: $e\n$st');
    }
  }

  Future<void> unregister() async {
    await _tokenSub?.cancel();
    _tokenSub = null;
    if (!await ensureFirebase()) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final userId = _client.auth.currentUser?.id;
      if (token != null && userId != null) {
        await _client
            .from('device_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('token', token);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e, st) {
      debugPrint('PushTokenService.unregister failed: $e\n$st');
    }
  }

  Future<void> _upsertToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : defaultTargetPlatform == TargetPlatform.android
            ? 'android'
            : null;
    if (platform == null) return;
    await _client.from('device_tokens').upsert(
      {
        'user_id': userId,
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,token',
    );
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    await _showFromMessage(message);
  }

  static void _onMessageOpened(RemoteMessage message) {
    // Local notif already shown; open handled by OS.
  }

  static Future<void> _showFromMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'] as String?;
    if (type == null) return;
    final title = data['title'] ??
        message.notification?.title ??
        'Alerta de glicose';
    final body = data['body'] ?? message.notification?.body ?? '';
    await LibreAlertService.showFromPush(
      type: type,
      title: title,
      body: body,
    );
  }
}

/// Background isolate entry for data-only FCM when app is killed/background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    return;
  }
  final data = message.data;
  final type = data['type'] as String?;
  if (type == null) return;
  await LibreAlertService.showFromPush(
    type: type,
    title: data['title'] ?? 'Alerta de glicose',
    body: data['body'] ?? '',
  );
}
