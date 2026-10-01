import 'session.dart';

/// Expected outcomes of `POST /auth/login`. Transport failures are thrown as
/// `ApiException` instead.
sealed class LoginResult {
  const LoginResult();
}

final class LoginSucceeded extends LoginResult {
  const LoginSucceeded(this.session);

  final Session session;
}

/// 401: wrong email or password.
final class LoginInvalidCredentials extends LoginResult {
  const LoginInvalidCredentials();
}

/// 423: locked after 5 failed attempts (NFR-02). The app shows the time left
/// and never retries on its own.
final class LoginLocked extends LoginResult {
  const LoginLocked({this.retryAfter});

  /// Null when the server does not say how long the lock lasts.
  final Duration? retryAfter;
}

/// Not a university address (BR-01).
final class LoginNotUniversityEmail extends LoginResult {
  const LoginNotUniversityEmail();
}
