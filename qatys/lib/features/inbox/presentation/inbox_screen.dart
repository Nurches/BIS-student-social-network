import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../../event/presentation/event_detail_screen.dart';
import '../../feed/presentation/feed_controller.dart';
import '../domain/app_notification.dart';
import 'inbox_controller.dart';

/// Every notification, also the ones whose push was missed (silent phone,
/// no connection at that moment). Opening it marks them as read.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final controller = ref.read(inboxProvider.notifier);
    try {
      await controller.refresh();
      await controller.markAllRead();
    } on Object {
      // The list keeps what it has; the error is shown by the provider.
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: switch (inbox) {
        AsyncData(:final value) when value.items.isEmpty => ListView(
          children: const [
            EmptyState(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              message:
                  'When a community you follow publishes an event, or you get '
                  'a place from the waiting list, it appears here.',
            ),
          ],
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: value.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) =>
                _NotificationTile(notification: value.items[i], now: now),
          ),
        ),
        AsyncError() => LoadFailure(
          message: 'Could not load the notifications.',
          onRetry: () => ref.invalidate(inboxProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.now});

  final AppNotification notification;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final promoted = notification.kind == NotificationKind.waitingListPromoted;
    return ListTile(
      minVerticalPadding: 12,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: promoted
            ? const Color(0xFFDDF3E4)
            : theme.colorScheme.primaryContainer,
        child: Icon(
          promoted ? Icons.celebration_outlined : Icons.campaign_outlined,
          color: promoted
              ? const Color(0xFF14532D)
              : theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        promoted
            ? 'You got a place: ${notification.eventTitle}'
            : 'New event: ${notification.eventTitle}',
        style: TextStyle(
          fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w800,
        ),
      ),
      subtitle: Text(
        '${notification.communityName} · '
        '${timeAgo(notification.createdAt, now)}',
      ),
      trailing: notification.isRead
          ? null
          : const Icon(
              Icons.circle,
              size: 12,
              color: AppTheme.accent,
              semanticLabel: 'New',
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(eventId: notification.eventId),
        ),
      ),
    );
  }
}

/// The bell on the feed, with the number of unread notifications.
class InboxButton extends ConsumerWidget {
  const InboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(inboxProvider).value?.unreadCount ?? 0;
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread new',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const InboxScreen())),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        backgroundColor: AppTheme.urgent,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
