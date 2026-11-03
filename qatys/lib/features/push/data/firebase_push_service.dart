import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/push_service.dart';

// firebase_messaging 17 deprecates the registration-token API in favour of
// register()/onRegistered, which hand out a Firebase Installation ID for a new
// "direct send" target. The server (docs/api.md, FCM HTTP v1 with `token`)
// and the course demo use the documented token path, which still works.
// Moving both sides to installation IDs is listed in docs/roadmap.md §8.
// ignore_for_file: deprecated_member_use

class FirebasePushService implements PushService {
  FirebasePushService(this._messaging);

  final FirebaseMessaging _messaging;

  /// Null when Firebase is not configured for this build (no
  /// `google-services.json`, or Web): the app then simply has no pushes.
  static Future<FirebasePushService?> tryCreate() async {
    if (kIsWeb) return null;
    try {
      await Firebase.initializeApp();
      return FirebasePushService(FirebaseMessaging.instance);
    } on Object catch (e) {
      debugPrint('Push disabled: Firebase is not configured ($e)');
      return null;
    }
  }

  @override
  bool get isAvailable => true;

  @override
  Future<bool> isPermitted() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Future<int?> initialEventId() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : eventIdFromData(message.data);
  }

  @override
  Stream<int> get openedEventIds => FirebaseMessaging.onMessageOpenedApp
      .map((m) => eventIdFromData(m.data))
      .where((id) => id != null)
      .cast<int>();

  @override
  Stream<PushNotice> get foregroundNotices => FirebaseMessaging.onMessage
      .map((m) {
        final id = eventIdFromData(m.data);
        if (id == null) return null;
        return PushNotice(
          title: m.notification?.title ?? 'New event',
          eventId: id,
        );
      })
      .where((n) => n != null)
      .cast<PushNotice>();

  @override
  Future<void> deleteToken() => _messaging.deleteToken();
}
