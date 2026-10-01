import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

typedef TokenReader = Future<String?> Function();

class ApiResponse {
  const ApiResponse(this.statusCode, this.body, {this.headers = const {}});

  final int statusCode;

  /// Response headers with lower-case names.
  final Map<String, String> headers;

  /// Decoded JSON, or null for an empty body.
  final Object? body;

  Map<String, Object?> get json {
    final body = this.body;
    if (body is Map<String, Object?>) return body;
    throw UnexpectedResponseException(
      'Expected a JSON object, got ${body.runtimeType}',
      statusCode: statusCode,
    );
  }
}

/// Thin JSON-over-HTTP client for docs/api.md.
///
/// Throws [ApiException] for transport failures, 5xx and, on authenticated
/// calls, 401. Every other status code is returned so that repositories can
/// map business answers (409, 410, ...) to domain values.
///
/// Calls with `authenticated: false` (`/auth/*`) send no token, and their 401
/// means wrong credentials, so it is returned like any other answer.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenReader readToken,
    Future<void> Function()? onUnauthorized,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUrl = baseUrl,
       _readToken = readToken,
       _onUnauthorized = onUnauthorized,
       _http = httpClient ?? http.Client();

  final String _baseUrl;
  final TokenReader _readToken;

  /// Called when an authenticated call gets 401: the session is over.
  final Future<void> Function()? _onUnauthorized;
  final http.Client _http;
  final Duration timeout;

  Future<ApiResponse> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<ApiResponse> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => _send('POST', path, body: body, authenticated: authenticated);

  Future<ApiResponse> delete(String path) => _send('DELETE', path);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';

    if (authenticated) {
      final token = await _readToken();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const NetworkException('The server did not answer in time');
    } on http.ClientException catch (e) {
      throw NetworkException(e.message);
    }

    final status = response.statusCode;
    if (status == 401 && authenticated) {
      await _onUnauthorized?.call();
      throw const UnauthorizedException();
    }
    if (status >= 500) {
      throw UnexpectedResponseException(
        'Server error $status',
        statusCode: status,
      );
    }

    return ApiResponse(status, _decode(response), headers: response.headers);
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      // A captive portal answers with its own HTML login page instead of our
      // JSON, so the phone looks online while the API is unreachable.
      throw const NetworkException('The response is not from our server');
    }
  }
}
