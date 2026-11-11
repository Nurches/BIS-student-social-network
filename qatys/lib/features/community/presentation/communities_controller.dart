import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';
import '../../event/domain/event.dart';
import '../../feed/presentation/feed_controller.dart';
import '../data/community_repository_provider.dart';
import '../domain/community.dart';

/// Every community with the student's follow state (Explore tab).
final communitiesProvider =
    AsyncNotifierProvider<CommunitiesController, List<Community>>(
      CommunitiesController.new,
      retry: (_, _) => null,
    );

class CommunitiesController extends AsyncNotifier<List<Community>> {
  @override
  Future<List<Community>> build() async {
    final studentId = ref.watch(
      sessionControllerProvider.select((s) => s.value?.student.id),
    );
    if (studentId == null) return const [];
    return ref.read(communityRepositoryProvider).fetchCommunities();
  }

  Future<void> refresh() async {
    final fresh = await ref
        .read(communityRepositoryProvider)
        .fetchCommunities();
    if (ref.mounted) state = AsyncData(fresh);
  }

  /// Follows or unfollows at once on the screen, then on the server; the
  /// screen goes back if the server cannot be reached. The feed is refreshed,
  /// so the community's events appear in it (or leave it) right away.
  Future<void> setSubscribed(
    int communityId, {
    required bool subscribed,
  }) async {
    final before = state.value;
    if (before == null) return;
    state = AsyncData([
      for (final c in before)
        c.id == communityId ? c.withSubscribed(subscribed) : c,
    ]);
    try {
      await ref
          .read(communityRepositoryProvider)
          .setSubscribed(communityId, subscribed: subscribed);
    } on Object {
      if (ref.mounted) state = AsyncData(before);
      rethrow;
    }
    unawaited(ref.read(feedControllerProvider.notifier).refresh());
  }
}

/// Open events of one community (community screen).
final communityEventsProvider = FutureProvider.autoDispose
    .family<List<Event>, int>(
      (ref, communityId) => ref
          .read(communityRepositoryProvider)
          .fetchCommunityEvents(communityId),
      retry: (_, _) => null,
    );
