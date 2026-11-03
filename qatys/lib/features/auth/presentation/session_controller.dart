import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../push/presentation/push_controller.dart';
import '../data/auth_providers.dart';
import '../domain/login_result.dart';
import '../domain/session.dart';
import '../domain/student.dart';

/// The signed-in student, or null. Restored from secure storage on launch.
final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final storage = ref.read(sessionStorageProvider);
    try {
      final session = await storage.read();
      if (session == null) return null;
      if (session.isExpired(DateTime.now())) {
        await storage.clear();
        return null;
      }
      return session;
    } on Exception {
      // A broken keystore (e.g. after a device restore) must not lock the
      // student out of the app: start over with a clean login.
      await storage.clear();
      return null;
    }
  }

  /// Transport failures are thrown as `ApiException` for the screen to show.
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    if (!isUniversityEmail(trimmedEmail)) {
      return const LoginNotUniversityEmail();
    }

    final result = await ref
        .read(authRepositoryProvider)
        .login(email: trimmedEmail, password: password);

    if (result is LoginSucceeded) {
      await ref.read(sessionStorageProvider).write(result.session);
      state = AsyncData(result.session);
    }
    return result;
  }

  bool _loggingOut = false;

  /// Brief §9, "Token on a shared device": nothing of this student stays on
  /// the phone — not the token, not the cached feed, not the offline queue,
  /// and the phone stops receiving their pushes.
  ///
  /// [reachServer] is false when the server already rejected the token
  /// (401), so the device-token removal is not even attempted.
  Future<void> logout({bool reachServer = true}) async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      await ref
          .read(pushControllerProvider.notifier)
          .onSignedOut(reachServer: reachServer);
      try {
        await ref.read(localStoreProvider).clearAll();
      } on Object {
        // The secure token below is what matters; never block a logout.
      }
      await ref.read(sessionStorageProvider).clear();
      state = const AsyncData(null);
    } finally {
      _loggingOut = false;
    }
  }
}
