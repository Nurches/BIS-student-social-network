import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/json_fields.dart';
import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

/// [NotificationRepository] backed by the FastAPI server (docs/api.md).
class HttpNotificationRepository implements NotificationRepository {
  HttpNotificationRepository(this._api);

  final ApiClient _api;

  @override
  Future<Inbox> fetchInbox() async {
    final response = await _api.get('/me/notifications');
    if (response.statusCode != 200) {
      throw UnexpectedResponseException(
        'Unexpected status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    try {
      return inboxFromJson(response.json);
    } on FormatException catch (e) {
      throw UnexpectedResponseException('Malformed inbox: ${e.message}');
    }
  }

  @override
  Future<void> markAllRead() async {
    final response = await _api.post('/me/notifications/read');
    if (response.statusCode != 204) {
      throw UnexpectedResponseException(
        'Unexpected status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }
}

/// Body of `GET /me/notifications`: `{ "items": [...], "unread_count": 1 }`.
Inbox inboxFromJson(Map<String, Object?> json) => Inbox(
  items: [
    for (final item in jsonObjects(json['items'], 'Notifications'))
      AppNotification(
        id: jsonField<int>(item, 'notification_id'),
        kind: switch (jsonField<String>(item, 'kind')) {
          'event_published' => NotificationKind.eventPublished,
          'waiting_list_promoted' => NotificationKind.waitingListPromoted,
          final other => throw FormatException('Unknown kind "$other"'),
        },
        eventId: jsonField<int>(item, 'event_id'),
        eventTitle: jsonField<String>(item, 'event_title'),
        communityName: jsonField<String>(item, 'community_name'),
        createdAt: jsonDateTime(item, 'created_at'),
        isRead: jsonField<bool>(item, 'is_read'),
      ),
  ],
  unreadCount: jsonField<int>(json, 'unread_count'),
);
