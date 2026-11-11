import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/date_format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/ui.dart';
import '../../event/domain/event.dart';
import '../../event/presentation/event_card.dart';
import '../../event/presentation/my_events_controller.dart';
import '../../home/presentation/home_tab_controller.dart';
import '../../inbox/presentation/inbox_controller.dart';
import '../../inbox/presentation/inbox_screen.dart';
import '../../sync/presentation/pending_actions_controller.dart';
import 'feed_controller.dart';

export '../../event/presentation/event_card.dart' show EventCard;

/// Quick filters above the feed; applied to the loaded events only.
enum FeedFilter { all, open, mine }

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late final AppLifecycleListener _lifecycle;
  FeedFilter _filter = FeedFilter.all;

  Future<void> _refreshAll() async {
    // The badge and My events follow the feed.
    ref.invalidate(myEventsProvider);
    await Future.wait([
      ref.read(feedControllerProvider.notifier).refresh(),
      ref.read(inboxProvider.notifier).refresh().catchError((Object _) {}),
    ]);
  }

  @override
  void initState() {
    super.initState();
    // Back from the background: the numbers may be stale and queued taps
    // may now get through.
    _lifecycle = AppLifecycleListener(onResume: _refreshAll);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/qatys_logo.png',
                width: 30,
                height: 30,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Qatys'),
          ],
        ),
        actions: [
          // No gesture-only paths (brief §8): pull to refresh has a button too.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          const InboxButton(),
        ],
      ),
      body: switch (feed) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: _refreshAll,
          child: _FeedList(
            state: value,
            filter: _filter,
            onFilter: (f) => setState(() => _filter = f),
          ),
        ),
        AsyncError(:final error) => _FirstLoadError(
          error: error,
          onRetry: () => ref.invalidate(feedControllerProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _FeedList extends ConsumerWidget {
  const _FeedList({
    required this.state,
    required this.filter,
    required this.onFilter,
  });

  final FeedState state;
  final FeedFilter filter;
  final ValueChanged<FeedFilter> onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingActionsProvider).value ?? const [];
    final now = ref.watch(clockProvider)();
    final controller = ref.read(feedControllerProvider.notifier);

    final header = <Widget>[
      if (state.refreshing) const LinearProgressIndicator(),
      if (state.problem case final problem?)
        _Banner(
          icon: Icons.cloud_off,
          text: switch (problem) {
            FeedProblem.noConnection =>
              'No connection to the server. Check the Wi-Fi login page or '
                  'switch to mobile data.',
            FeedProblem.serverError =>
              'The server had a problem. Showing the last saved events.',
          },
          actionLabel: 'Retry',
          onAction: controller.refresh,
        ),
      if (state.savedAt case final savedAt? when !state.refreshing)
        _Banner(
          icon: Icons.history,
          text: 'Saved events from ${formatDateTime(savedAt)}.',
        ),
      if (pending.isNotEmpty)
        _Banner(
          icon: Icons.schedule_send,
          text: pending.length == 1
              ? '"${pending.first.eventTitle}": waiting to be sent.'
              : '${pending.length} actions waiting to be sent.',
          actionLabel: 'Send now',
          onAction: controller.refresh,
        ),
    ];

    if (state.events.isEmpty) {
      // A ListView, so pull to refresh still works on the empty state.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ...header,
          EmptyState(
            icon: Icons.event_available,
            title: 'No upcoming events',
            message:
                'Events from the communities you follow appear here as soon '
                'as they are published. You get a notification too.',
            actionLabel: 'Find communities to follow',
            onAction: () =>
                ref.read(homeTabProvider.notifier).select(HomeTab.explore),
          ),
        ],
      );
    }

    final events = switch (filter) {
      FeedFilter.all => state.events,
      FeedFilter.open => state.events.where((e) => !e.isFull).toList(),
      FeedFilter.mine =>
        state.events.where((e) => e.myState != RegistrationState.none).toList(),
    };
    header.addAll([
      _Greeting(now: now, count: state.events.length),
      _Filters(selected: filter, onSelected: onFilter),
      if (events.isEmpty)
        EmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'Nothing here',
          message: filter == FeedFilter.mine
              ? 'You have not registered for any of these events yet.'
              : 'Every event in your feed is full right now.',
          actionLabel: 'Show all events',
          onAction: () => onFilter(FeedFilter.all),
        ),
    ]);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: header.length + events.length + 1,
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        final i = index - header.length;
        if (i < events.length) {
          return EventCard(event: events[i], now: now);
        }
        if (!state.hasMore) return const SizedBox(height: 8);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: state.loadingMore ? null : controller.loadMore,
            child: state.loadingMore
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('Load more events'),
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                text,
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
          ),
          if (actionLabel case final label?)
            TextButton(onPressed: onAction, child: Text(label)),
        ],
      ),
    );
  }
}

class _FirstLoadError extends StatelessWidget {
  const _FirstLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(
            error is NetworkException
                ? 'No connection to the server. Check the Wi-Fi login page '
                      'or switch to mobile data.'
                : 'Something went wrong on the server.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.now, required this.count});

  final DateTime now;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = now.hour;
    final hello = hour < 5
        ? 'Good night'
        : hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hello, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            count == 1
                ? '1 event open for registration'
                : '$count events open for registration',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelected});

  final FeedFilter selected;
  final ValueChanged<FeedFilter> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        for (final (filter, label) in const [
          (FeedFilter.all, 'All'),
          (FeedFilter.open, 'Places left'),
          (FeedFilter.mine, 'My registrations'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: selected == filter,
              onSelected: (_) => onSelected(filter),
            ),
          ),
      ],
    ),
  );
}
