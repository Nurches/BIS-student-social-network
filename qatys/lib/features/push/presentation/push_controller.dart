import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../data/device_token_repository.dart';
import '../domain/push_service.dart';

/// True while the app should show the "turn on notifications" prompt.
final pushControllerProvider = NotifierProvider<PushController, bool>(
  PushController.new,
);

/// Links this phone to the signed-in student for FR-01: asks for the
/// permission once after the first login (brief §7), sends the FCM token to
/// the server, keeps it current, and takes it back on logout.
class PushController extends Notifier<bool> {
  static const askedKey = 'push.permission_asked';

  StreamSubscription<String>? _refreshes;

  PushService get _push => ref.read(pushServiceProvider);
  DeviceTokenRepository get _tokens => ref.read(deviceTokenRepositoryProvider);

  @override
  bool build() {
    ref.onDispose(() => unawaited(_refreshes?.cancel()));
    return false;
  }

  Future<void> onSignedIn() async {
    if (!_push.isAvailable) return;
    final asked = await ref.read(localStoreProvider).read(askedKey) != null;
    if (!asked) {
      state = true;
    } else if (await _push.isPermitted()) {
      await _registerToken();
    }
  }

  /// The student answered our one-sentence explanation.
  Future<void> answerPrompt({required bool allow}) async {
    state = false;
    await ref.read(localStoreProvider).write(askedKey, allow ? 'yes' : 'no');
    if (allow && await _push.requestPermission()) await _registerToken();
  }

  /// [reachServer] is false when the session is already invalid (a 401), so
  /// the server cannot be asked; deleting the FCM token still makes the
  /// server drop it on its next send.
  Future<void> onSignedOut({required bool reachServer}) async {
    state = false;
    // Not awaited: nothing depends on the cancellation finishing.
    unawaited(_refreshes?.cancel());
    _refreshes = null;
    if (!_push.isAvailable) return;
    try {
      final token = await _push.token();
      if (reachServer && token != null) await _tokens.delete(token);
    } on Object catch (e) {
      debugPrint('Device token not removed from the server: $e');
    }
    try {
      await _push.deleteToken();
    } on Object catch (e) {
      debugPrint('FCM token not deleted: $e');
    }
  }

  Future<void> _registerToken() async {
    try {
      final token = await _push.token();
      if (token != null) await _tokens.save(token);
    } on Object catch (e) {
      // Not fatal: retried on the next launch and on every token refresh.
      debugPrint('Device token not sent: $e');
    }
    unawaited(_refreshes?.cancel());
    _refreshes = _push.tokenRefreshes.listen((token) async {
      try {
        await _tokens.save(token);
      } on Object catch (e) {
        debugPrint('Refreshed device token not sent: $e');
      }
    });
  }
}
