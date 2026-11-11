import '../../event/domain/event.dart';
import 'community.dart';

/// Implementations: `HttpCommunityRepository` (real server) and
/// `MockEventRepository` (the in-memory server of mock mode).
/// Transport failures are thrown as `ApiException`.
abstract interface class CommunityRepository {
  /// Every community, ordered by name, with the student's follow state.
  Future<List<Community>> fetchCommunities();

  /// Follow (`true`) or unfollow (`false`); safe to repeat.
  Future<void> setSubscribed(int communityId, {required bool subscribed});

  /// Open events of one community, also when the student does not follow it.
  Future<List<Event>> fetchCommunityEvents(int communityId);
}
