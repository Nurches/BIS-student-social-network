import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/ui.dart';
import '../../feed/presentation/feed_controller.dart';
import '../../home/presentation/home_tab_controller.dart';
import 'event_card.dart';
import 'my_events_controller.dart';

/// My events tab: where the student is registered or waiting, upcoming first.
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(myEventsProvider);
    final now = ref.watch(clockProvider)();
    Future<void> reload() => ref.refresh(myEventsProvider.future);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My events'),
        actions: [
          IconButton(
            tooltip: 'Refresh my events',
            icon: const Icon(Icons.refresh),
            onPressed: reload,
          ),
        ],
      ),
      body: switch (events) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (value.isEmpty)
                EmptyState(
                  icon: Icons.confirmation_number_outlined,
                  title: 'No registrations yet',
                  message:
                      'Register for an event and it shows up here, with your '
                      'place on the waiting list if it is full.',
                  actionLabel: 'Browse the feed',
                  onAction: () =>
                      ref.read(homeTabProvider.notifier).select(HomeTab.feed),
                )
              else ...[
                for (final (title, list) in [
                  (
                    'Upcoming',
                    value.where((e) => e.startsAt.isAfter(now)).toList(),
                  ),
                  (
                    'Past',
                    value.where((e) => !e.startsAt.isAfter(now)).toList(),
                  ),
                ])
                  if (list.isNotEmpty) ...[
                    SectionTitle('$title (${list.length})'),
                    for (final event in list)
                      EventCard(
                        event: event,
                        now: now,
                        onReturn: () => ref.invalidate(myEventsProvider),
                      ),
                  ],
              ],
            ],
          ),
        ),
        AsyncError(:final error) => LoadFailure(
          message: error is NetworkException
              ? 'No connection to the server. Check the Wi-Fi login page or '
                    'switch to mobile data.'
              : 'Something went wrong on the server.',
          onRetry: () => ref.invalidate(myEventsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
