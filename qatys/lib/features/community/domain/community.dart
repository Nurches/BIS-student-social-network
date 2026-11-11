/// A club or office that publishes events (docs/api.md, `GET /communities`).
class Community {
  const Community({
    required this.id,
    required this.name,
    required this.description,
    required this.isConfirmed,
    required this.subscriberCount,
    required this.upcomingEvents,
    required this.isSubscribed,
  });

  final int id;
  final String name;
  final String description;

  /// Confirmed by the Student Union, so it may publish events (BR-01).
  final bool isConfirmed;
  final int subscriberCount;

  /// Published events whose registration deadline has not passed.
  final int upcomingEvents;
  final bool isSubscribed;

  /// The same community after the student followed or unfollowed it.
  Community withSubscribed(bool value) => Community(
    id: id,
    name: name,
    description: description,
    isConfirmed: isConfirmed,
    subscriberCount:
        subscriberCount + (value == isSubscribed ? 0 : (value ? 1 : -1)),
    upcomingEvents: upcomingEvents,
    isSubscribed: value,
  );
}
