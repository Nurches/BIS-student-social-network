/// Failures of the transport or of the session, as opposed to expected
/// business answers (a full event, a passed deadline) which repositories
/// return as values.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server could not be reached: no network, timeout, or a captive-portal
/// Wi-Fi answering instead of our API (brief, section 9).
final class NetworkException extends ApiException {
  const NetworkException(super.message);
}

/// 401: the token is missing, expired or revoked. The app must log out.
final class UnauthorizedException extends ApiException {
  const UnauthorizedException() : super('Unauthorized');
}

/// 404: the resource does not exist or is no longer published.
final class NotFoundException extends ApiException {
  const NotFoundException(super.message);
}

/// Any other status code, or a body that does not match the contract.
final class UnexpectedResponseException extends ApiException {
  const UnexpectedResponseException(super.message, {this.statusCode});

  final int? statusCode;
}
