enum NotificationKind {
  /// A community the student follows published an event (FR-01).
  eventPublished,

  /// A place was freed and the student moved up from the waiting list.
  waitingListPromoted,

  /// Week 12: an event the student registered for is cancelled.
  eventCancelled,

  /// Week 12: an event the student registered for moved to a new time.
  eventRescheduled,

  /// Week 12: the Student Union approved the student's community request.
  communityApproved,
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
    this.communityId,
    this.startsAt,
    this.previousStartsAt,
  });

  final int id;
  final NotificationKind kind;

  /// Null only for [NotificationKind.communityApproved].
  final int? eventId;
  final String? eventTitle;
  final int? communityId;
  final String communityName;

  /// The event start now, and before the last move.
  final DateTime? startsAt;
  final DateTime? previousStartsAt;
  final DateTime createdAt;
  final bool isRead;

  AppNotification read() => AppNotification(
    id: id,
    kind: kind,
    eventId: eventId,
    eventTitle: eventTitle,
    communityId: communityId,
    communityName: communityName,
    startsAt: startsAt,
    previousStartsAt: previousStartsAt,
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
