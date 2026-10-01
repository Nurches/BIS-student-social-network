import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';

typedef TokenReader = Future<String?> Function();

class ApiResponse {
  const ApiResponse(this.statusCode, this.body);

  final int statusCode;

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
/// Throws [ApiException] for transport failures, 401 and 5xx. Every other
/// status code is returned so that repositories can map business answers
/// (409, 410, ...) to domain values.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenReader readToken,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUrl = baseUrl,
       _readToken = readToken,
       _http = httpClient ?? http.Client();

  final String _baseUrl;
  final TokenReader _readToken;
  final http.Client _http;
  final Duration timeout;

  Future<ApiResponse> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<ApiResponse> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<ApiResponse> delete(String path) => _send('DELETE', path);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';

    final token = await _readToken();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
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
    if (status == 401) throw const UnauthorizedException();
    if (status >= 500) {
      throw UnexpectedResponseException(
        'Server error $status',
        statusCode: status,
      );
    }

    return ApiResponse(status, _decode(response));
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

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(
    baseUrl: config.apiBaseUrl,
    // Wired to secure token storage in step 3 (login).
    readToken: () async => null,
  );
});
