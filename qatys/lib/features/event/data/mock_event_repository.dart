import '../../../core/network/api_exception.dart';
import '../../community/domain/community.dart';
import '../../community/domain/community_repository.dart';
import '../../inbox/domain/app_notification.dart';
import '../../inbox/domain/notification_repository.dart';
import '../domain/event.dart';
import '../domain/event_repository.dart';
import '../domain/registration_result.dart';

/// The in-memory server of mock mode. It behaves like docs/api.md: it owns
/// `freePlaces`, enforces the limit and the deadline, keeps a waiting list,
/// the student's subscriptions and inbox. Data mirrors the seed in
/// server/seed.py, seen by student 1, plus events that cover every demo
/// scenario. Dates are relative to the moment the repository is created, so
/// the demo never goes stale.
class MockEventRepository
    implements EventRepository, CommunityRepository, NotificationRepository {
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
  final Map<int, _MockCommunity> _communities = {};

  /// Communities student 1 follows; the feed shows only their events.
  final Set<int> _subscribed = {1, 2};
  final List<AppNotification> _inbox = [];

  @override
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor}) async {
    await _delay();
    final now = _now();
    final visible =
        _events.values
            .where(
              (e) =>
                  _subscribed.contains(e.community.id) &&
                  now.isBefore(e.registrationDeadline),
            )
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

  @override
  Future<List<Event>> fetchMyEvents() async {
    await _delay();
    return [
      for (final e in _events.values)
        if (e.myState != RegistrationState.none) e.toEvent(),
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  // ---------- CommunityRepository ----------

  @override
  Future<List<Community>> fetchCommunities() async {
    await _delay();
    final now = _now();
    return [
      for (final c in _communities.values)
        Community(
          id: c.id,
          name: c.name,
          description: c.description,
          isConfirmed: c.confirmed,
          subscriberCount:
              c.otherFollowers + (_subscribed.contains(c.id) ? 1 : 0),
          upcomingEvents: _events.values
              .where(
                (e) =>
                    e.community.id == c.id &&
                    now.isBefore(e.registrationDeadline),
              )
              .length,
          isSubscribed: _subscribed.contains(c.id),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> setSubscribed(
    int communityId, {
    required bool subscribed,
  }) async {
    await _delay();
    if (!_communities.containsKey(communityId)) {
      throw NotFoundException('Community $communityId not found');
    }
    subscribed ? _subscribed.add(communityId) : _subscribed.remove(communityId);
  }

  @override
  Future<List<Event>> fetchCommunityEvents(int communityId) async {
    await _delay();
    if (!_communities.containsKey(communityId)) {
      throw NotFoundException('Community $communityId not found');
    }
    final now = _now();
    return [
      for (final e in _events.values)
        if (e.community.id == communityId &&
            now.isBefore(e.registrationDeadline))
          e.toEvent(),
    ]..sort((a, b) => a.registrationDeadline.compareTo(b.registrationDeadline));
  }

  // ---------- NotificationRepository ----------

  @override
  Future<Inbox> fetchInbox() async {
    await _delay();
    final items = [..._inbox]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Inbox(
      items: items,
      unreadCount: items.where((n) => !n.isRead).length,
    );
  }

  @override
  Future<void> markAllRead() async {
    await _delay();
    for (var i = 0; i < _inbox.length; i++) {
      _inbox[i] = _inbox[i].read();
    }
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
    const sportsClub = (id: 4, name: 'Sports Club');
    const volunteerHub = (id: 5, name: 'Volunteer Hub');

    for (final community in [
      _MockCommunity(
        1,
        'IT Club',
        'Programming contests, hackathons and workshops',
        otherFollowers: 41,
      ),
      _MockCommunity(
        2,
        'Career Center',
        'Internships, job fairs, CV clinics',
        otherFollowers: 87,
      ),
      _MockCommunity(
        3,
        'Debate Society',
        'Weekly debates and tournaments',
        confirmed: false,
        otherFollowers: 12,
      ),
      _MockCommunity(
        4,
        'Sports Club',
        'Futsal, volleyball and the KBTU running club',
        otherFollowers: 56,
      ),
      _MockCommunity(
        5,
        'Volunteer Hub',
        'Charity drives, campus clean-ups and mentoring',
        otherFollowers: 23,
      ),
    ]) {
      _communities[community.id] = community;
    }

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
      // Communities student 1 does not follow yet: found in Explore.
      _MockEvent(
        id: 7,
        community: sportsClub,
        title: 'Futsal cup',
        description: '5-a-side tournament between faculties. Teams of 5 to 7.',
        location: 'Sports hall',
        startsAt: now.add(const Duration(days: 8)),
        registrationDeadline: now.add(const Duration(days: 6)),
        participantLimit: 40,
        confirmed: 4,
      ),
      _MockEvent(
        id: 8,
        community: volunteerHub,
        title: 'Campus clean-up day',
        description: 'Two hours outdoors, gloves and tea provided.',
        location: 'Main entrance',
        startsAt: now.add(const Duration(days: 5)),
        registrationDeadline: now.add(const Duration(days: 3)),
        participantLimit: 25,
        confirmed: 2,
      ),
    ]) {
      _events[event.id] = event;
    }

    _inbox.addAll([
      AppNotification(
        id: 3,
        kind: NotificationKind.eventPublished,
        eventId: 6,
        eventTitle: 'Flutter workshop',
        communityName: itClub.name,
        createdAt: now.subtract(const Duration(hours: 2)),
        isRead: false,
      ),
      AppNotification(
        id: 2,
        kind: NotificationKind.eventPublished,
        eventId: 5,
        eventTitle: 'CV clinic',
        communityName: careerCenter.name,
        createdAt: now.subtract(const Duration(days: 1)),
        isRead: true,
      ),
      AppNotification(
        id: 1,
        kind: NotificationKind.eventPublished,
        eventId: 1,
        eventTitle: 'Autumn Hackathon 2026',
        communityName: itClub.name,
        createdAt: now.subtract(const Duration(days: 2)),
        isRead: true,
      ),
    ]);
  }
}

class _MockCommunity {
  _MockCommunity(
    this.id,
    this.name,
    this.description, {
    this.confirmed = true,
    this.otherFollowers = 0,
  });

  final int id;
  final String name;
  final String description;
  final bool confirmed;

  /// Followers other than the signed-in student.
  final int otherFollowers;
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
