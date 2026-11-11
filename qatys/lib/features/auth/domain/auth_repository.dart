import 'login_result.dart';
import 'register_result.dart';

/// Implementations: `HttpAuthRepository` (real server) and
/// `MockAuthRepository` (in-memory fake for the demo).
abstract interface class AuthRepository {
  Future<LoginResult> login({required String email, required String password});

  /// Creates an account; the caller signs in with the same credentials.
  Future<RegisterResult> register({
    required String email,
    required String password,
    required String fullName,
  });
}
