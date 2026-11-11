import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../../event/presentation/event_card.dart';
import '../../feed/presentation/feed_controller.dart';
import 'communities_controller.dart';
import 'explore_screen.dart';
import 'follow_button.dart';

/// One community: who it is, follow / unfollow, and its open events — also
/// for a student who does not follow it yet.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({required this.communityId, super.key});

  final int communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final community = ref
        .watch(communitiesProvider)
        .value
        ?.where((c) => c.id == communityId)
        .firstOrNull;
    final events = ref.watch(communityEventsProvider(communityId));
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final color = communityColor(communityId);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(communityEventsProvider(communityId));
          await ref.read(communitiesProvider.notifier).refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 168,
              foregroundColor: Colors.white,
              backgroundColor: color,
              title: Text(community?.name ?? 'Community'),
              titleTextStyle: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: CommunityAvatar(
                          communityId: communityId,
                          name: community?.name ?? '?',
                          size: 60,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (community != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (community.description.isNotEmpty)
                        Text(
                          community.description,
                          style: theme.textTheme.bodyLarge,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        communityStats(community),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!community.isConfirmed) ...[
                        const SizedBox(height: 12),
                        const Pill(
                          text: 'Not confirmed by the Student Union yet',
                          icon: Icons.info_outline,
                          background: Color(0xFFFFF1D6),
                          foreground: Color(0xFF7A4B00),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FollowButton(community: community, expanded: true),
                      const SizedBox(height: 4),
                      Text(
                        community.isSubscribed
                            ? 'Its events are in your feed, and you get a '
                                  'notification for each new one.'
                            : 'Follow to see its events in your feed and get '
                                  'a notification for each new one.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SectionTitle('Open events')),
            switch (events) {
              AsyncData(:final value) when value.isEmpty =>
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.event_busy,
                    title: 'No open events right now',
                    message:
                        'New events appear here as soon as they are '
                        'published.',
                  ),
                ),
              AsyncData(:final value) => SliverList.list(
                children: [
                  for (final event in value)
                    EventCard(
                      event: event,
                      now: now,
                      onReturn: () =>
                          ref.invalidate(communityEventsProvider(communityId)),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
              AsyncError() => SliverToBoxAdapter(
                child: LoadFailure(
                  message: 'Could not load the events.',
                  onRetry: () =>
                      ref.invalidate(communityEventsProvider(communityId)),
                ),
              ),
              _ => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }
}
