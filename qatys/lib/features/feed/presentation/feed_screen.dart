import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/date_format.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/presentation/session_controller.dart';
import '../../event/domain/event.dart';
import '../../event/presentation/event_detail_screen.dart';
import '../../sync/presentation/pending_actions_controller.dart';
import 'feed_controller.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the background: the numbers may be stale and queued taps
    // may now get through.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(feedControllerProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Qatys'),
        actions: [
          // No gesture-only paths (brief §8): pull to refresh has a button too.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refresh,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: switch (feed) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: controller.refresh,
          child: _FeedList(state: value),
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
  const _FeedList({required this.state});

  final FeedState state;

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
        children: [...header, const _EmptyState()],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: header.length + state.events.length + 1,
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        final i = index - header.length;
        if (i < state.events.length) {
          return EventCard(event: state.events[i], now: now);
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

/// Brief §7: community, title, start date, deadline, free places.
class EventCard extends StatelessWidget {
  const EventCard({required this.event, required this.now, super.key});

  final Event event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = switch (event.myState) {
      RegistrationState.registered => 'Registered ✓',
      RegistrationState.waitingList =>
        event.waitingPosition == null
            ? 'Waiting list'
            : 'Waiting list · #${event.waitingPosition}',
      RegistrationState.none => null,
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailScreen(eventId: event.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      event.communityName,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  if (status != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(event.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Starts ${formatDateTime(event.startsAt)}'),
              Text(
                'Register by ${formatDateTime(event.registrationDeadline)} '
                '(${timeLeft(event.registrationDeadline, now)})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                event.isFull
                    ? 'Full · waiting list open'
                    : '${event.freePlaces} of ${event.participantLimit} '
                          'places free',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: event.isFull ? colors.error : null,
                ),
              ),
            ],
          ),
        ),
      ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
    child: Column(
      children: [
        const Icon(Icons.event_available, size: 56),
        const SizedBox(height: 16),
        Text(
          'No upcoming events',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Events from the communities you follow appear here as soon as '
          'they are published. You get a notification too.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
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
