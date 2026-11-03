import '../../../core/network/api_exception.dart';
import '../domain/event.dart';
import '../domain/event_repository.dart';
import '../domain/registration_result.dart';

/// In-memory [EventRepository] that behaves like the server in docs/api.md:
/// it owns `freePlaces`, enforces the limit and the deadline, and keeps a
/// waiting list. Data mirrors the seed in docs/schema.sql, seen by student 1,
/// plus events that cover every demo scenario. Dates are relative to the
/// moment the repository is created, so the demo never goes stale.
class MockEventRepository implements EventRepository {
  MockEventRepository({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 400),
  }) : _now = clock ?? DateTime.now {
    _seed();
  }

  final DateTime Function() _now;

  /// Simulated network delay, so loading states are visible in the demo.
  final Duration latency;

  final Map<int, _MockEvent> _events = {};

  @override
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor}) async {
    await _delay();
    final now = _now();
    final visible =
        _events.values
            .where((e) => now.isBefore(e.registrationDeadline))
            .toList()
          ..sort(
            (a, b) => a.registrationDeadline.compareTo(b.registrationDeadline),
          );

    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit).clamp(0, visible.length);
    return FeedPage(
      items: [for (final e in visible.sublist(start, end)) e.toEvent()],
      nextCursor: end < visible.length ? '$end' : null,
    );
  }

  @override
  Future<Event> fetchEvent(int id) async {
    await _delay();
    return _find(id).toEvent();
  }

  @override
  Future<RegistrationResult> register(int eventId) async {
    await _delay();
    final event = _find(eventId);

    if (!_now().isBefore(event.registrationDeadline)) {
      return const RegistrationClosed();
    }
    if (event.myState != RegistrationState.none) {
      return const RegistrationAlreadyExists();
    }
    if (event.confirmed >= event.participantLimit) {
      event
        ..waiting += 1
        ..myState = RegistrationState.waitingList
        ..myPosition = event.waiting;
      return RegistrationWaitListed(position: event.waiting);
    }
    event
      ..confirmed += 1
      ..myState = RegistrationState.registered;
    return const RegistrationConfirmed();
  }

  @override
  Future<CancelResult> cancelRegistration(int eventId) async {
    await _delay();
    final event = _find(eventId);

    if (event.myState == RegistrationState.none) {
      return const CancelNotRegistered();
    }
    if (!_now().isBefore(event.startsAt)) return const CancelEventStarted();

    switch (event.myState) {
      case RegistrationState.none:
        break;
      case RegistrationState.waitingList:
        event.waiting -= 1;
      case RegistrationState.registered:
        event.confirmed -= 1;
        // The server promotes the oldest waiting-list entry in the same
        // transaction (docs/api.md, DELETE /events/{id}/registrations).
        if (event.waiting > 0) {
          event
            ..waiting -= 1
            ..confirmed += 1;
        }
    }
    event
      ..myState = RegistrationState.none
      ..myPosition = null;
    return const CancelSucceeded();
  }

  /// Demo and test hook: another student takes a place, e.g. to show the
  /// race on the last place (brief, section 9).
  void takePlaceByAnotherStudent(int eventId) {
    final event = _find(eventId);
    if (event.confirmed < event.participantLimit) {
      event.confirmed += 1;
    } else {
      event.waiting += 1;
    }
  }

  _MockEvent _find(int id) =>
      _events[id] ?? (throw NotFoundException('Event $id not found'));

  Future<void> _delay() => Future<void>.delayed(latency);

  void _seed() {
    final now = _now();
    const itClub = (id: 1, name: 'IT Club');
    const careerCenter = (id: 2, name: 'Career Center');

    for (final event in [
      _MockEvent(
        id: 1,
        community: itClub,
        title: 'Autumn Hackathon 2026',
        description: '24-hour team hackathon',
        location: 'Block C, room 301',
        startsAt: now.add(const Duration(days: 14)),
        registrationDeadline: now.add(const Duration(days: 10)),
        participantLimit: 30,
        confirmed: 3,
      ),
      _MockEvent(
        id: 2,
        community: careerCenter,
        title: 'IT Career Day',
        description: 'Meeting with 12 companies',
        location: 'Main hall',
        startsAt: now.add(const Duration(days: 7)),
        registrationDeadline: now.add(const Duration(days: 5)),
        participantLimit: 200,
        confirmed: 1,
      ),
      // Deadline passed: hidden from the feed, but still opened from an old
      // push notification. Renders the closed state (FR-02).
      _MockEvent(
        id: 3,
        community: itClub,
        title: 'Git workshop for first-years',
        description: 'Basics of version control',
        location: 'Block A, room 105',
        startsAt: now.add(const Duration(days: 3)),
        registrationDeadline: now.subtract(const Duration(days: 1)),
        participantLimit: 25,
        confirmed: 25,
      ),
      // Full: registration lands on the waiting list (FR-03).
      _MockEvent(
        id: 5,
        community: careerCenter,
        title: 'CV clinic',
        description: 'One-to-one CV review with recruiters',
        location: 'Block B, room 210',
        startsAt: now.add(const Duration(days: 4)),
        registrationDeadline: now.add(const Duration(days: 2)),
        participantLimit: 12,
        confirmed: 12,
        waiting: 2,
      ),
      // One place left, deadline today: the race on the last place.
      _MockEvent(
        id: 6,
        community: itClub,
        title: 'Flutter workshop',
        description: 'Build and ship your first mobile app in two hours',
        location: 'Block C, room 204',
        startsAt: now.add(const Duration(days: 1)),
        registrationDeadline: now.add(const Duration(hours: 6)),
        participantLimit: 20,
        confirmed: 19,
      ),
    ]) {
      _events[event.id] = event;
    }
  }
}

class _MockEvent {
  _MockEvent({
    required this.id,
    required this.community,
    required this.title,
    required this.description,
    required this.location,
    required this.startsAt,
    required this.registrationDeadline,
    required this.participantLimit,
    required this.confirmed,
    this.waiting = 0,
  });

  final int id;
  final ({int id, String name}) community;
  final String title;
  final String description;
  final String location;
  final DateTime startsAt;
  final DateTime registrationDeadline;
  final int participantLimit;

  int confirmed;
  int waiting;
  RegistrationState myState = RegistrationState.none;
  int? myPosition;

  Event toEvent() => Event(
    id: id,
    communityId: community.id,
    communityName: community.name,
    title: title,
    description: description,
    location: location,
    startsAt: startsAt,
    registrationDeadline: registrationDeadline,
    participantLimit: participantLimit,
    freePlaces: (participantLimit - confirmed).clamp(0, participantLimit),
    myState: myState,
    waitingPosition: myPosition,
  );
}
