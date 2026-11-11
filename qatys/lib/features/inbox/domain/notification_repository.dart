import 'app_notification.dart';

/// Implementations: `HttpNotificationRepository` and `MockEventRepository`.
abstract interface class NotificationRepository {
  /// Newest first, at most 50.
  Future<Inbox> fetchInbox();

  Future<void> markAllRead();
}
