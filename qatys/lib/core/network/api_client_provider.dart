import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/session_controller.dart';
import '../config/app_config.dart';
import 'api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(
    baseUrl: config.apiBaseUrl,
    // Read lazily on every call: the session can change while the client lives.
    readToken: () async => ref.read(sessionControllerProvider).value?.token,
    onUnauthorized: () => ref.read(sessionControllerProvider.notifier).logout(),
  );
});
