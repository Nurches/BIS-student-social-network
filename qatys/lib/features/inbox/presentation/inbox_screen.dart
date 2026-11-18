import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../../community/presentation/community_screen.dart';
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
                  'New events of the communities you follow, a place from the '
                  'waiting list, a cancelled or moved event and the answer to '
                  'your community request appear here.',
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
    final n = notification;
    final look = switch (n.kind) {
      NotificationKind.eventPublished => (
        icon: Icons.campaign_outlined,
        background: theme.colorScheme.primaryContainer,
        foreground: theme.colorScheme.onPrimaryContainer,
        title: 'New event: ${n.eventTitle}',
      ),
      NotificationKind.waitingListPromoted => (
        icon: Icons.celebration_outlined,
        background: const Color(0xFFDDF3E4),
        foreground: const Color(0xFF14532D),
        title: 'You got a place: ${n.eventTitle}',
      ),
      NotificationKind.eventCancelled => (
        icon: Icons.event_busy,
        background: const Color(0xFFFDE2E1),
        foreground: const Color(0xFF8A1C1C),
        title: 'Cancelled: ${n.eventTitle}',
      ),
      NotificationKind.eventRescheduled => (
        icon: Icons.update,
        background: const Color(0xFFFFF1D6),
        foreground: const Color(0xFF7A4B00),
        title: n.startsAt == null
            ? 'Moved: ${n.eventTitle}'
            : 'Moved: ${n.eventTitle} · now ${formatDateTime(n.startsAt!)}',
      ),
      NotificationKind.communityApproved => (
        icon: Icons.verified_outlined,
        background: const Color(0xFFDDF3E4),
        foreground: const Color(0xFF14532D),
        title: 'Approved: ${n.communityName} is now a community',
      ),
    };
    return ListTile(
      minVerticalPadding: 12,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: look.background,
        child: Icon(look.icon, color: look.foreground),
      ),
      title: Text(
        look.title,
        style: TextStyle(
          fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800,
        ),
      ),
      subtitle: Text(
        n.kind == NotificationKind.communityApproved
            ? 'Student Union · ${timeAgo(n.createdAt, now)}'
            : '${n.communityName} · ${timeAgo(n.createdAt, now)}',
      ),
      trailing: n.isRead
          ? null
          : const Icon(
              Icons.circle,
              size: 12,
              color: AppTheme.accent,
              semanticLabel: 'New',
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => switch ((n.eventId, n.communityId)) {
            (final int eventId, _) => EventDetailScreen(eventId: eventId),
            (null, final int communityId) => CommunityScreen(
              communityId: communityId,
            ),
            _ => const InboxScreen(),
          },
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
