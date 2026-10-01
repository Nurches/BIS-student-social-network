import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client_provider.dart';
import '../domain/event_repository.dart';
import 'http_event_repository.dart';
import 'mock_event_repository.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) return MockEventRepository();
  return HttpEventRepository(ref.watch(apiClientProvider));
});
