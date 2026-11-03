import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/core/network/reachability.dart';

HealthCheckProbe probe(http.Response Function(http.Request) answer) =>
    HealthCheckProbe(
      ApiClient(
        baseUrl: 'https://api.test/api/v1',
        readToken: () async => null,
        httpClient: MockClient((request) async => answer(request)),
      ),
    );

void main() {
  test('reachable only on 200 {"status": "ok"} from GET /health', () async {
    late http.Request seen;
    final reachable = await probe((request) {
      seen = request;
      return http.Response('{"status":"ok"}', 200);
    }).isServerReachable();

    expect(reachable, isTrue);
    expect(seen.url.path, '/api/v1/health');
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('captive-portal Wi-Fi answering with its HTML page is not reachable '
      '(brief §9)', () async {
    final reachable = await probe(
      (_) => http.Response('<html>Log in to KBTU Wi-Fi</html>', 200),
    ).isServerReachable();
    expect(reachable, isFalse);
  });

  test('database down (503) is not reachable', () async {
    final reachable = await probe(
      (_) => http.Response(
        '{"status":"unavailable","error":"database_unavailable"}',
        503,
      ),
    ).isServerReachable();
    expect(reachable, isFalse);
  });

  test('no network is not reachable', () async {
    final reachable = await probe(
      (_) => throw http.ClientException('Failed host lookup'),
    ).isServerReachable();
    expect(reachable, isFalse);
  });
}
