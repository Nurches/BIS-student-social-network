import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/core/network/api_exception.dart';

void main() {
  late int unauthorizedCalls;

  ApiClient clientWith(MockClientHandler handler) => ApiClient(
    baseUrl: 'https://api.test/api/v1',
    readToken: () async => 'jwt',
    onUnauthorized: () async => unauthorizedCalls++,
    httpClient: MockClient(handler),
  );

  setUp(() => unauthorizedCalls = 0);

  test('401 on an authenticated call ends the session', () async {
    final client = clientWith((_) async => http.Response('', 401));

    await expectLater(
      client.get('/feed'),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(unauthorizedCalls, 1);
  });

  test('401 on an unauthenticated call is returned as an answer', () async {
    final client = clientWith((_) async => http.Response('', 401));

    final response = await client.post('/auth/login', authenticated: false);

    expect(response.statusCode, 401);
    expect(unauthorizedCalls, 0);
  });

  test('a dropped connection becomes NetworkException', () {
    final client = clientWith((_) async => throw http.ClientException('down'));

    expect(client.get('/feed'), throwsA(isA<NetworkException>()));
  });

  test('5xx becomes UnexpectedResponseException', () {
    final client = clientWith((_) async => http.Response('', 503));

    expect(client.get('/feed'), throwsA(isA<UnexpectedResponseException>()));
  });
}
