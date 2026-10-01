/// The student's own relation to an event, always as reported by the server.
enum RegistrationState { none, registered, waitingList }

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
  });

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

  bool get isFull => freePlaces <= 0;

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
