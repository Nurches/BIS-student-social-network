import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/core/network/api_exception.dart';
import 'package:qatys/features/push/data/device_token_repository.dart';

void main() {
  late List<http.Request> requests;

  HttpDeviceTokenRepository answering(int status) => HttpDeviceTokenRepository(
    ApiClient(
      baseUrl: 'https://api.test/api/v1',
      readToken: () async => 'jwt',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', status);
      }),
    ),
  );

  setUp(() => requests = []);

  test('PUT /me/device-token with the token and platform', () async {
    await answering(204).save('fcm-1');

    final request = requests.single;
    expect(request.method, 'PUT');
    expect(request.url.path, '/api/v1/me/device-token');
    expect(request.headers['Authorization'], 'Bearer jwt');
    expect(jsonDecode(request.body), {'token': 'fcm-1', 'platform': 'android'});
  });

  test('an unexpected answer is reported', () {
    expect(
      answering(422).save('fcm-1'),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });

  test('DELETE /me/device-token on logout', () async {
    await answering(204).delete('fcm-1');

    expect(requests.single.method, 'DELETE');
    expect(jsonDecode(requests.single.body), {'token': 'fcm-1'});
  });
}
