/// Status of a community (schema v4). Any student can request one; it is
/// `pending` until a Student Union moderator approves or rejects it.
enum CommunityStatus { pending, confirmed, rejected }

CommunityStatus communityStatusFromJson(String value) => switch (value) {
  'pending' => CommunityStatus.pending,
  'confirmed' => CommunityStatus.confirmed,
  'rejected' => CommunityStatus.rejected,
  _ => throw FormatException('Unknown community status "$value"'),
};

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
    this.status = CommunityStatus.confirmed,
    this.isMine = false,
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

  /// Others see only confirmed communities; the owner also sees a pending one.
  final CommunityStatus status;

  /// The signed-in student requested (owns) this community.
  final bool isMine;

  bool get isPending => status == CommunityStatus.pending;

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
    status: status,
    isMine: isMine,
  );
}

/// A community the student asked the Student Union for (Week 12).
class CommunityRequest {
  const CommunityRequest({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    required this.createdAt,
    this.rejectReason,
    this.reviewedAt,
  });

  final int id;
  final String name;
  final String description;
  final CommunityStatus status;
  final DateTime createdAt;

  /// Written by the moderator on a rejection; shown to the student.
  final String? rejectReason;
  final DateTime? reviewedAt;
}

/// `GET /me/community-requests`.
class CommunityRequests {
  const CommunityRequests({required this.items, required this.pendingLimit});

  static const empty = CommunityRequests(items: [], pendingLimit: 3);

  final List<CommunityRequest> items;

  /// At most this many requests may wait at once (3 on the server).
  final int pendingLimit;

  int get pendingCount =>
      items.where((r) => r.status == CommunityStatus.pending).length;

  bool get canRequestMore => pendingCount < pendingLimit;
}

/// Outcome of `POST /communities`. Errors the student can fix are values.
sealed class CommunityRequestResult {
  const CommunityRequestResult();
}

/// 201: the request waits for a moderator.
final class CommunityRequestSent extends CommunityRequestResult {
  const CommunityRequestSent(this.request);

  final CommunityRequest request;
}

/// 409 `community_name_taken` (names are compared ignoring case).
final class CommunityNameTaken extends CommunityRequestResult {
  const CommunityNameTaken();
}

/// 409 `too_many_pending_requests`: 3 requests already wait.
final class CommunityRequestLimitReached extends CommunityRequestResult {
  const CommunityRequestLimitReached();
}
