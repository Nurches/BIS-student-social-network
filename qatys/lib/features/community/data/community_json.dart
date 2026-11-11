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
);
