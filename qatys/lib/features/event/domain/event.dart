/// The student's own relation to an event, always as reported by the server.
enum RegistrationState { none, registered, waitingList }

/// `status` of the Event object (schema v4). A cancelled event is still
/// shown to the students registered for it, with the reason it is gone.
enum EventStatus { published, cancelled }

class Event {
  const Event({
    required this.id,
    required this.communityId,
    required this.communityName,
    required this.title,
    required this.description,
    required this.location,
    required this.startsAt,
    required this.registrationDeadline,
    required this.participantLimit,
    required this.freePlaces,
    required this.myState,
    this.waitingPosition,
    this.status = EventStatus.published,
    this.previousStartsAt,
    this.cancelledAt,
    DateTime? endsAt,
    this.posterUrl,
    this.checkedInAt,
    this.myRating,
    this.feedbackOpen = false,
  }) : _endsAt = endsAt;

  final int id;
  final int communityId;
  final String communityName;
  final String title;
  final String description;
  final String? location;
  final DateTime startsAt;
  final DateTime registrationDeadline;
  final int participantLimit;

  /// Server-computed. Never derived or adjusted on the client (brief, section 4).
  final int freePlaces;
  final RegistrationState myState;

  /// Position in the waiting list, present only when [myState] is
  /// [RegistrationState.waitingList].
  final int? waitingPosition;

  final EventStatus status;

  /// The start before the organiser last moved the event; null if never moved.
  final DateTime? previousStartsAt;
  final DateTime? cancelledAt;

  final DateTime? _endsAt;

  /// Week 13: when the event ends. The server sends it; an older server or
  /// cache has none, then it is two hours after the start (as on the server).
  DateTime get endsAt => _endsAt ?? startsAt.add(const Duration(hours: 2));

  /// Path of the poster image on the API host (`/api/v1/events/{id}/poster?v=…`),
  /// null without a poster: the community's colours are shown instead.
  final String? posterUrl;

  /// When the organiser checked the student in at the door (FR-06).
  final DateTime? checkedInAt;

  /// The student's own rating 1–5, once sent (FR-07).
  final int? myRating;

  /// Server-computed: checked in, the event ended, not rated yet. The client
  /// shows the "Rate this event" button only then.
  final bool feedbackOpen;

  bool get isCheckedIn => checkedInAt != null;

  bool get hasPoster => posterUrl != null;

  bool hasEnded(DateTime now) => !now.isBefore(endsAt);

  bool get isFull => freePlaces <= 0;

  bool get isCancelled => status == EventStatus.cancelled;

  bool get isRescheduled => previousStartsAt != null;

  /// Used only to render a past deadline as closed (FR-02). Whether a
  /// registration succeeds is always decided by the server.
  bool isDeadlinePassed(DateTime now) => !now.isBefore(registrationDeadline);
}

class FeedPage {
  const FeedPage({required this.items, required this.nextCursor});

  final List<Event> items;

  /// Null when there are no more pages.
  final String? nextCursor;
}
