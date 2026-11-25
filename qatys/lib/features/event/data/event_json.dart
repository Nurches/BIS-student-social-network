import '../domain/event.dart';
import '../domain/registration_result.dart';
import '../domain/ticket.dart';

/// The Event object of the feed and detail responses (docs/api.md).
/// `community_name`, `free_places`, `my_status` and `waiting_position` are
/// computed by the server.
Event eventFromJson(Map<String, Object?> json) {
  return Event(
    id: _field<int>(json, 'event_id'),
    communityId: _field<int>(json, 'community_id'),
    communityName: _field<String>(json, 'community_name'),
    title: _field<String>(json, 'title'),
    description: _field<String?>(json, 'description') ?? '',
    location: _field<String?>(json, 'location'),
    startsAt: _dateTime(json, 'starts_at'),
    registrationDeadline: _dateTime(json, 'registration_deadline'),
    participantLimit: _field<int>(json, 'participant_limit'),
    freePlaces: _field<int>(json, 'free_places'),
    myState: _registrationState(_field<String?>(json, 'my_status')),
    waitingPosition: _field<int?>(json, 'waiting_position'),
    // v4 fields; an older server (or an older cached feed) has none of them.
    status: switch (json['status']) {
      null || 'published' => EventStatus.published,
      'cancelled' => EventStatus.cancelled,
      final other => throw FormatException('Unknown event status "$other"'),
    },
    previousStartsAt: _optionalDateTime(json, 'previous_starts_at'),
    cancelledAt: _optionalDateTime(json, 'cancelled_at'),
    // v5 fields (Week 13); absent on an older server or cache.
    endsAt: _optionalDateTime(json, 'ends_at'),
    posterUrl: json['poster_url'] as String?,
    checkedInAt: _optionalDateTime(json, 'checked_in_at'),
    myRating: json['my_rating'] as int?,
    feedbackOpen: json['feedback_open'] as bool? ?? false,
  );
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) =>
    json[key] == null ? null : _dateTime(json, key);

/// The inverse of [eventFromJson], for the offline feed cache.
Map<String, Object?> eventToJson(Event event) => {
  'event_id': event.id,
  'community_id': event.communityId,
  'community_name': event.communityName,
  'title': event.title,
  'description': event.description,
  'location': event.location,
  'starts_at': event.startsAt.toUtc().toIso8601String(),
  'registration_deadline': event.registrationDeadline.toUtc().toIso8601String(),
  'participant_limit': event.participantLimit,
  'free_places': event.freePlaces,
  'my_status': switch (event.myState) {
    RegistrationState.none => null,
    RegistrationState.registered => 'confirmed',
    RegistrationState.waitingList => 'waiting_list',
  },
  'waiting_position': event.waitingPosition,
  'status': event.status.name,
  'previous_starts_at': event.previousStartsAt?.toUtc().toIso8601String(),
  'cancelled_at': event.cancelledAt?.toUtc().toIso8601String(),
  'ends_at': event.endsAt.toUtc().toIso8601String(),
  'poster_url': event.posterUrl,
  'checked_in_at': event.checkedInAt?.toUtc().toIso8601String(),
  'my_rating': event.myRating,
  'feedback_open': event.feedbackOpen,
};

/// Body of `GET /feed` (docs/api.md): `{ "items": [...], "next_cursor": ... }`,
/// where `next_cursor` is opaque and `null` on the last page.
FeedPage feedPageFromJson(Map<String, Object?> json) {
  final items = _field<List<Object?>>(json, 'items');
  return FeedPage(
    items: [
      for (final item in items)
        if (item is Map<String, Object?>)
          eventFromJson(item)
        else
          throw FormatException('Feed item is not an object: $item'),
    ],
    nextCursor: _field<Object?>(json, 'next_cursor')?.toString(),
  );
}

/// `{ "items": [Event, ...] }` of `GET /me/registrations` and
/// `GET /communities/{id}/events` (docs/api.md).
List<Event> eventListFromJson(Map<String, Object?> json) => [
  for (final item in _field<List<Object?>>(json, 'items'))
    if (item is Map<String, Object?>)
      eventFromJson(item)
    else
      throw FormatException('Event item is not an object: $item'),
];

/// Body of `200` from `POST /events/{id}/registrations` (docs/api.md).
RegistrationWaitListed waitListedFromJson(Map<String, Object?> json) =>
    RegistrationWaitListed(position: _field<int>(json, 'position'));

/// Maps `registration.status` from docs/schema.sql.
RegistrationState _registrationState(String? status) => switch (status) {
  'confirmed' => RegistrationState.registered,
  'waiting_list' => RegistrationState.waitingList,
  null || 'cancelled' || 'none' => RegistrationState.none,
  _ => throw FormatException('Unknown registration status "$status"'),
};

// docs/api.md: every timestamp is ISO 8601 with an offset
// (e.g. `2026-11-20T10:00:00+05:00`). A value without one would be read as
// device-local time.
DateTime _dateTime(Map<String, Object?> json, String key) {
  final raw = _field<String>(json, key);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('Field "$key" is not a date: $raw');
  return parsed.toLocal();
}

T _field<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException(
    'Field "$key" expected $T, got ${value.runtimeType}: $value',
  );
}

/// Body of `GET /events/{id}/ticket` (docs/api.md, Week 13).
Ticket ticketFromJson(Map<String, Object?> json) => Ticket(
  eventId: _field<int>(json, 'event_id'),
  registrationId: _field<int>(json, 'registration_id'),
  code: _field<String>(json, 'code'),
  qr: _field<String>(json, 'qr'),
  checkedInAt: _optionalDateTime(json, 'checked_in_at'),
  checkInOpensAt: _dateTime(json, 'check_in_opens_at'),
  checkInClosesAt: _dateTime(json, 'check_in_closes_at'),
);

/// The inverse of [ticketFromJson], for the offline copy of a ticket.
Map<String, Object?> ticketToJson(Ticket ticket) => {
  'event_id': ticket.eventId,
  'registration_id': ticket.registrationId,
  'code': ticket.code,
  'qr': ticket.qr,
  'checked_in_at': ticket.checkedInAt?.toUtc().toIso8601String(),
  'check_in_opens_at': ticket.checkInOpensAt.toUtc().toIso8601String(),
  'check_in_closes_at': ticket.checkInClosesAt.toUtc().toIso8601String(),
};
