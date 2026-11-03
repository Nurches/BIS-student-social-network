import '../domain/event.dart';
import '../domain/registration_result.dart';

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
  );
}

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
