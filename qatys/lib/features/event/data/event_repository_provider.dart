import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client_provider.dart';
import '../domain/event_repository.dart';
import 'http_event_repository.dart';
import 'mock_event_repository.dart';

/// The in-memory server of mock mode, shared by every mock repository so that
/// following a community changes the feed, like on the real server.
final mockServerProvider = Provider<MockEventRepository>(
  (ref) => MockEventRepository(),
);

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) return ref.watch(mockServerProvider);
  return HttpEventRepository(ref.watch(apiClientProvider));
});
