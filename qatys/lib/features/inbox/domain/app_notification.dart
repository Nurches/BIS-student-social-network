enum NotificationKind {
  /// A community the student follows published an event (FR-01).
  eventPublished,

  /// A place was freed and the student moved up from the waiting list.
  waitingListPromoted,
}

/// One row of the in-app inbox: the same notifications the pushes were sent
/// for, so nothing is lost when a push was missed (silent phone, no network).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.eventId,
    required this.eventTitle,
    required this.communityName,
    required this.createdAt,
    required this.isRead,
  });

  final int id;
  final NotificationKind kind;
  final int eventId;
  final String eventTitle;
  final String communityName;
  final DateTime createdAt;
  final bool isRead;

  AppNotification read() => AppNotification(
    id: id,
    kind: kind,
    eventId: eventId,
    eventTitle: eventTitle,
    communityName: communityName,
    createdAt: createdAt,
    isRead: true,
  );
}

class Inbox {
  const Inbox({required this.items, required this.unreadCount});

  static const empty = Inbox(items: [], unreadCount: 0);

  final List<AppNotification> items;
  final int unreadCount;
}
