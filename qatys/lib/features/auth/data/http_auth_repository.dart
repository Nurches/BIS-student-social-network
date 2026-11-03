import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/auth_repository.dart';
import '../domain/login_result.dart';
import 'auth_json.dart';

/// [AuthRepository] backed by the FastAPI server (docs/api.md).
class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );

    switch (response.statusCode) {
      case 200:
        try {
          return LoginSucceeded(sessionFromJson(response.json));
        } on FormatException catch (e) {
          throw UnexpectedResponseException('Malformed login: ${e.message}');
        }
      case 401:
        return const LoginInvalidCredentials();
      case 422:
        return const LoginNotUniversityEmail();
      case 423:
        return LoginLocked(retryAfter: _retryAfter(response));
      default:
        throw UnexpectedResponseException(
          'Unexpected login status ${response.statusCode}',
          statusCode: response.statusCode,
        );
    }
  }

  // docs/api.md: 423 carries a `retry_after_minutes` body field and the
  // standard `Retry-After` header (seconds); the body wins, the header is the
  // fallback, so the app can show the minutes left (NFR-02).
  Duration? _retryAfter(ApiResponse response) {
    final body = response.body;
    if (body is Map<String, Object?>) {
      final minutes = body['retry_after_minutes'];
      if (minutes is int) return Duration(minutes: minutes);
    }
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
