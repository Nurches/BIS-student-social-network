import '../../../core/network/json_fields.dart';
import '../domain/community.dart';

/// One item of `GET /communities` (docs/api.md).
Community communityFromJson(Map<String, Object?> json) => Community(
  id: jsonField<int>(json, 'community_id'),
  name: jsonField<String>(json, 'name'),
  description: jsonField<String?>(json, 'description') ?? '',
  isConfirmed: jsonField<bool>(json, 'is_confirmed'),
  subscriberCount: jsonField<int>(json, 'subscriber_count'),
  upcomingEvents: jsonField<int>(json, 'upcoming_events'),
  isSubscribed: jsonField<bool>(json, 'is_subscribed'),
  // v4; an older server sends only is_confirmed.
  status: json['status'] == null
      ? (jsonField<bool>(json, 'is_confirmed')
            ? CommunityStatus.confirmed
            : CommunityStatus.pending)
      : communityStatusFromJson(jsonField<String>(json, 'status')),
  isMine: json['is_mine'] == true,
);

/// The body of `POST /communities` (201) and one item of
/// `GET /me/community-requests`.
CommunityRequest communityRequestFromJson(Map<String, Object?> json) =>
    CommunityRequest(
      id: jsonField<int>(json, 'community_id'),
      name: jsonField<String>(json, 'name'),
      description: jsonField<String?>(json, 'description') ?? '',
      status: communityStatusFromJson(jsonField<String>(json, 'status')),
      rejectReason: jsonField<String?>(json, 'reject_reason'),
      createdAt: jsonDateTime(json, 'created_at'),
      reviewedAt: json['reviewed_at'] == null
          ? null
          : jsonDateTime(json, 'reviewed_at'),
    );

CommunityRequests communityRequestsFromJson(Map<String, Object?> json) =>
    CommunityRequests(
      items: [
        for (final item in jsonObjects(json['items'], 'Community requests'))
          communityRequestFromJson(item),
      ],
      pendingLimit: jsonField<int>(json, 'pending_limit'),
    );
