import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'api_client.dart';
import 'api_client_provider.dart';
import 'api_exception.dart';

/// Brief, section 9 ("Captive-portal Wi-Fi"): the connectivity flag lies when
/// the university Wi-Fi shows its login page. The server counts as reachable
/// only after our own `GET /health` answers `200 {"status": "ok"}`.
abstract interface class ReachabilityProbe {
  Future<bool> isServerReachable();
}

class HealthCheckProbe implements ReachabilityProbe {
  HealthCheckProbe(this._api);

  final ApiClient _api;

  @override
  Future<bool> isServerReachable() async {
    try {
      final response = await _api.get('/health', authenticated: false);
      final body = response.body;
      return response.statusCode == 200 &&
          body is Map<String, Object?> &&
          body['status'] == 'ok';
    } on ApiException {
      return false;
    }
  }
}

/// Mock mode has no server to lose.
class AlwaysReachable implements ReachabilityProbe {
  const AlwaysReachable();

  @override
  Future<bool> isServerReachable() async => true;
}

final reachabilityProbeProvider = Provider<ReachabilityProbe>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) return const AlwaysReachable();
  return HealthCheckProbe(ref.watch(apiClientProvider));
});
