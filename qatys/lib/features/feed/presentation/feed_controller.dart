import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/presentation/session_controller.dart';
import '../../event/data/event_repository_provider.dart';
import '../../event/domain/event.dart';
import '../../sync/presentation/pending_actions_controller.dart';
import '../data/feed_cache.dart';

enum FeedProblem {
  /// No answer from our server: offline, captive portal, timeout.
  noConnection,

  /// The server answered with an error.
  serverError,
}

class FeedState {
  const FeedState({
    required this.events,
    this.nextCursor,
    this.savedAt,
    this.refreshing = false,
    this.loadingMore = false,
    this.problem,
  });

  final List<Event> events;
  final String? nextCursor;

  /// Set while the list comes from the cache and not from the server.
  final DateTime? savedAt;
  final bool refreshing;
  final bool loadingMore;

  /// Why the last refresh failed; the list still shows what we have.
  final FeedProblem? problem;

  bool get hasMore => nextCursor != null;

  FeedState copyWith({
    List<Event>? events,
    String? Function()? nextCursor,
    DateTime? Function()? savedAt,
    bool? refreshing,
    bool? loadingMore,
    FeedProblem? Function()? problem,
  }) => FeedState(
    events: events ?? this.events,
    nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
    savedAt: savedAt != null ? savedAt() : this.savedAt,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    problem: problem != null ? problem() : this.problem,
  );
}

final feedControllerProvider = AsyncNotifierProvider<FeedController, FeedState>(
  FeedController.new,
  // Errors are shown with a Retry button; no silent automatic retries.
  retry: (_, _) => null,
);

/// Cache-first feed (NFR-01): the saved first page is shown at once, then
/// refreshed from the server in the background.
class FeedController extends AsyncNotifier<FeedState> {
  static const pageSize = 20;

  DateTime Function() get _now => ref.read(clockProvider);

  @override
  Future<FeedState> build() async {
    final studentId = ref.watch(
      sessionControllerProvider.select((s) => s.value?.student.id),
    );
    if (studentId == null) return const FeedState(events: []);

    final snapshot = await ref
        .read(feedCacheProvider)
        .read(studentId, now: _now());
    if (snapshot != null) {
      unawaited(Future.microtask(refresh));
      return FeedState(
        events: snapshot.events,
        savedAt: snapshot.savedAt,
        refreshing: true,
      );
    }
    // Nothing saved yet: the first page is the only thing to wait for.
    return _loadFirstPage(studentId);
  }

  /// Pull to refresh, the refresh button and coming back to the app. Sends
  /// the offline queue first, so the list includes those registrations.
  Future<void> refresh() async {
    final current = state.value;
    final studentId = ref.read(sessionControllerProvider).value?.student.id;
    if (current == null || studentId == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(current.copyWith(refreshing: true));
    try {
      await ref.read(pendingActionsProvider.notifier).flush();
      final fresh = await _loadFirstPage(studentId);
      if (ref.mounted) state = AsyncData(fresh);
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(refreshing: false, problem: () => _problemOf(e)),
      );
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(eventRepositoryProvider)
          .fetchFeed(limit: pageSize, cursor: current.nextCursor);
      if (!ref.mounted) return;
      final known = {for (final e in current.events) e.id};
      state = AsyncData(
        current.copyWith(
          events: [
            ...current.events,
            for (final e in page.items)
              if (!known.contains(e.id)) e,
          ],
          nextCursor: () => page.nextCursor,
          loadingMore: false,
          problem: () => null,
        ),
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(loadingMore: false, problem: () => _problemOf(e)),
      );
    }
  }

  /// The detail screen re-fetched [event]: show the same numbers on the card.
  void replaceEvent(Event event) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        events: [for (final e in current.events) e.id == event.id ? event : e],
      ),
    );
  }

  Future<FeedState> _loadFirstPage(int studentId) async {
    final page = await ref
        .read(eventRepositoryProvider)
        .fetchFeed(limit: pageSize);
    await ref.read(feedCacheProvider).write(studentId, page.items, _now());
    return FeedState(events: page.items, nextCursor: page.nextCursor);
  }

  static FeedProblem _problemOf(ApiException e) => switch (e) {
    NetworkException() => FeedProblem.noConnection,
    _ => FeedProblem.serverError,
  };
}

/// The current time; overridden in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
