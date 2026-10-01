import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client_provider.dart';
import '../domain/auth_repository.dart';
import 'http_auth_repository.dart';
import 'mock_auth_repository.dart';
import 'session_storage.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) return MockAuthRepository();
  return HttpAuthRepository(ref.watch(apiClientProvider));
});

final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SecureSessionStorage(),
);
