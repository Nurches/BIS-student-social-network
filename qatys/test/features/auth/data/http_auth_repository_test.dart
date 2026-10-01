import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/features/auth/data/http_auth_repository.dart';
import 'package:qatys/features/auth/domain/login_result.dart';

void main() {
  late List<http.Request> requests;
  late int unauthorizedCalls;

  HttpAuthRepository repositoryAnswering(
    int status, {
    Object? body,
    Map<String, String> headers = const {},
  }) {
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: headers,
      );
    });
    return HttpAuthRepository(
      ApiClient(
        baseUrl: 'https://api.test/api/v1',
        readToken: () async => 'stale-token',
        onUnauthorized: () async => unauthorizedCalls++,
        httpClient: client,
      ),
    );
  }

  Future<LoginResult> login(HttpAuthRepository repository) =>
      repository.login(email: 'nurassyl@kbtu.kz', password: 'secret');

  setUp(() {
    requests = [];
    unauthorizedCalls = 0;
  });

  test('200 returns a session; no token is sent to /auth/login', () async {
    final result = await login(
      repositoryAnswering(
        200,
        body: {
          'token': 'jwt',
          'student': {
            'student_id': 1,
            'email': 'nurassyl@kbtu.kz',
            'full_name': 'Turarbek Nurassyl',
          },
        },
      ),
    );

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/auth/login');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(request.body), {
      'email': 'nurassyl@kbtu.kz',
      'password': 'secret',
    });

    final session = (result as LoginSucceeded).session;
    expect(session.token, 'jwt');
    expect(session.student.id, 1);
  });

  test('401 means wrong credentials, not an expired session', () async {
    expect(
      await login(repositoryAnswering(401)),
      isA<LoginInvalidCredentials>(),
    );
    expect(unauthorizedCalls, 0);
  });

  test('423 with retry_after_minutes', () async {
    final result = await login(
      repositoryAnswering(423, body: {'retry_after_minutes': 12}),
    );
    expect((result as LoginLocked).retryAfter, const Duration(minutes: 12));
  });

  test('423 with a Retry-After header', () async {
    final result = await login(
      repositoryAnswering(423, headers: {'retry-after': '90'}),
    );
    expect((result as LoginLocked).retryAfter, const Duration(seconds: 90));
  });

  test('423 without a duration', () async {
    final result = await login(repositoryAnswering(423));
    expect((result as LoginLocked).retryAfter, isNull);
  });
}
