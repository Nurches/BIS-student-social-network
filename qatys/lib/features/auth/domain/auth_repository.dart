import 'login_result.dart';

/// Implementations: `HttpAuthRepository` (real server) and
/// `MockAuthRepository` (in-memory fake for the demo).
abstract interface class AuthRepository {
  Future<LoginResult> login({required String email, required String password});
}
