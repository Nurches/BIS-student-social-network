/// Expected outcomes of `POST /auth/register` (docs/api.md). Transport
/// failures are thrown as `ApiException`.
sealed class RegisterResult {
  const RegisterResult();
}

/// 201: the account exists and can sign in at once.
final class RegisterCreated extends RegisterResult {
  const RegisterCreated();
}

/// The account was created and the app signed in with it (session stored).
final class RegisterSignedIn extends RegisterResult {
  const RegisterSignedIn();
}

/// 409 `email_already_registered`.
final class RegisterEmailTaken extends RegisterResult {
  const RegisterEmailTaken();
}

/// 422 `not_a_university_email` (BR-01).
final class RegisterNotUniversityEmail extends RegisterResult {
  const RegisterNotUniversityEmail();
}

/// 422 `password_too_short` (under 8) or `password_too_long` (over 72 bytes).
final class RegisterBadPassword extends RegisterResult {
  const RegisterBadPassword({required this.tooShort});

  final bool tooShort;
}
