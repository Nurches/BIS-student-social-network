import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client_provider.dart';
import '../../event/data/event_repository_provider.dart';
import '../domain/notification_repository.dart';
import 'http_notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) return ref.watch(mockServerProvider);
  return HttpNotificationRepository(ref.watch(apiClientProvider));
});
