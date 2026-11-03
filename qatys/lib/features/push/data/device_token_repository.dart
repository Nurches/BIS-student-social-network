import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_client_provider.dart';
import '../../../core/network/api_exception.dart';

/// `PUT` / `DELETE /me/device-token` (docs/api.md, FR-01).
abstract interface class DeviceTokenRepository {
  Future<void> save(String token);

  Future<void> delete(String token);
}

class HttpDeviceTokenRepository implements DeviceTokenRepository {
  HttpDeviceTokenRepository(this._api);

  final ApiClient _api;

  static String get _platform => switch (defaultTargetPlatform) {
    _ when kIsWeb => 'web',
    TargetPlatform.iOS => 'ios',
    _ => 'android',
  };

  @override
  Future<void> save(String token) async {
    final response = await _api.put(
      '/me/device-token',
      body: {'token': token, 'platform': _platform},
    );
    if (response.statusCode != 204) {
      throw UnexpectedResponseException(
        'Device token not saved: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<void> delete(String token) async {
    await _api.delete('/me/device-token', body: {'token': token});
  }
}

/// Mock mode: there is no server to tell.
class NoopDeviceTokenRepository implements DeviceTokenRepository {
  const NoopDeviceTokenRepository();

  @override
  Future<void> save(String token) async {}

  @override
  Future<void> delete(String token) async {}
}

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return const NoopDeviceTokenRepository();
  }
  return HttpDeviceTokenRepository(ref.watch(apiClientProvider));
});
