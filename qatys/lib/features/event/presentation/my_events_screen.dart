import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/ui.dart';
import '../../feed/presentation/feed_controller.dart';
import '../../home/presentation/home_tab_controller.dart';
import '../data/event_repository_provider.dart';
import '../domain/event.dart';
import 'event_card.dart';
import 'feedback_sheet.dart';
import 'my_events_controller.dart';
import 'ticket_screen.dart';

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
                  // Week 13: an event stays "Upcoming" until it ends, so
                  // the ticket is at hand at the door.
                  (
                    'Upcoming',
                    value
                        .where((e) => !e.isCancelled && !e.hasEnded(now))
                        .toList(),
                  ),
                  // Week 12: kept, so the student sees why an event is gone.
                  ('Cancelled', value.where((e) => e.isCancelled).toList()),
                  (
                    'Past',
                    value
                        .where((e) => !e.isCancelled && e.hasEnded(now))
                        .toList(),
                  ),
                ])
                  if (list.isNotEmpty) ...[
                    SectionTitle('$title (${list.length})'),
                    for (final event in list)
                      EventCard(
                        event: event,
                        now: now,
                        onReturn: () => ref.invalidate(myEventsProvider),
                        footer: _footer(context, ref, event, now),
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

/// Week 13: the ticket of a confirmed upcoming place, the rating button of
/// an attended event, the rating already given.
Widget? _footer(
  BuildContext context,
  WidgetRef ref,
  Event event,
  DateTime now,
) {
  if (event.isCancelled || event.myState != RegistrationState.registered) {
    return null;
  }
  if (event.feedbackOpen) {
    return FilledButton.tonalIcon(
      key: ValueKey('rate-${event.id}'),
      onPressed: () async {
        final result = await showFeedbackSheet(
          context,
          eventTitle: event.title,
          send: (rating, comment) => ref
              .read(eventRepositoryProvider)
              .sendFeedback(event.id, rating: rating, comment: comment),
        );
        if (result == null || !context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(feedbackMessage(result))));
        ref.invalidate(myEventsProvider);
      },
      icon: const Icon(Icons.star_rounded),
      label: const Text('Rate this event'),
    );
  }
  if (event.myRating case final rating?) {
    return Row(
      key: ValueKey('rated-${event.id}'),
      children: [
        const Text(
          'Your rating ',
          style: TextStyle(
            color: Color(0xFFB45309),
            fontWeight: FontWeight.w700,
          ),
        ),
        StarRow(rating: rating),
      ],
    );
  }
  if (event.isCheckedIn) {
    return const Row(
      children: [
        Icon(Icons.verified, size: 18, color: Color(0xFF14532D)),
        SizedBox(width: 6),
        Text(
          'Checked in',
          style: TextStyle(
            color: Color(0xFF14532D),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
  if (event.hasEnded(now)) return null;
  return OutlinedButton.icon(
    key: ValueKey('ticket-${event.id}'),
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => TicketScreen(event: event))),
    icon: const Icon(Icons.qr_code_2),
    label: const Text('Show ticket'),
  );
}
