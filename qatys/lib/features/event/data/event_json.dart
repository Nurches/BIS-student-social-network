import '../domain/event.dart';
import '../domain/registration_result.dart';

// TODO(confirm): docs/api.md does not define the event object in feed and
// detail responses. Field names follow docs/schema.sql columns in snake_case,
// as the rest of api.md does; `community_name`, `free_places`, `my_status`
// and `waiting_position` are computed by the server.
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

// TODO(confirm): feed envelope `{ "items": [...], "next_cursor": "..." }`.
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

// TODO(confirm): schema.sql uses TIMESTAMP without time zone. The server must
// send ISO 8601 with an offset (e.g. `2026-10-08T10:00:00+05:00`); a value
// without one is read as device-local time.
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
