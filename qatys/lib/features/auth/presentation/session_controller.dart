import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> logout() async {
    await ref.read(sessionStorageProvider).clear();
    state = const AsyncData(null);
  }
}
