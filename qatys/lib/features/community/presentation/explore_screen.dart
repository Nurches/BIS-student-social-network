import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/ui.dart';
import '../domain/community.dart';
import 'communities_controller.dart';
import 'community_screen.dart';
import 'follow_button.dart';

/// Explore tab: find clubs and offices to follow. Following a community is
/// what fills the feed and turns on its pushes.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final communities = ref.watch(communitiesProvider);
    final controller = ref.read(communitiesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          IconButton(
            tooltip: 'Refresh communities',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refresh,
          ),
        ],
      ),
      body: switch (communities) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: controller.refresh,
          child: _List(
            communities: value,
            query: _query,
            onQuery: (q) => setState(() => _query = q),
          ),
        ),
        AsyncError(:final error) => LoadFailure(
          message: error is NetworkException
              ? 'No connection to the server. Check the Wi-Fi login page or '
                    'switch to mobile data.'
              : 'Something went wrong on the server.',
          onRetry: () => ref.invalidate(communitiesProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.communities,
    required this.query,
    required this.onQuery,
  });

  final List<Community> communities;
  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final matching = communities
        .where(
          (c) =>
              q.isEmpty ||
              c.name.toLowerCase().contains(q) ||
              c.description.toLowerCase().contains(q),
        )
        .toList();
    final following = matching.where((c) => c.isSubscribed).toList();
    final others = matching.where((c) => !c.isSubscribed).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: TextField(
            onChanged: onQuery,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search clubs and offices',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        if (matching.isEmpty)
          const EmptyState(
            icon: Icons.search_off,
            title: 'Nothing found',
            message: 'Try another word, for example "club" or "career".',
          ),
        if (following.isNotEmpty) ...[
          SectionTitle('Following (${following.length})'),
          for (final c in following) CommunityTile(community: c),
        ],
        if (others.isNotEmpty) ...[
          const SectionTitle('Discover'),
          for (final c in others) CommunityTile(community: c),
        ],
      ],
    );
  }
}

class CommunityTile extends StatelessWidget {
  const CommunityTile({required this.community, super.key});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CommunityScreen(communityId: community.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CommunityAvatar(
                      communityId: community.id,
                      name: community.name,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  community.name,
                                  style: theme.textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (community.isConfirmed) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                  semanticLabel:
                                      'Confirmed by the Student Union',
                                ),
                              ],
                            ],
                          ),
                          if (community.description.isNotEmpty)
                            Text(
                              community.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        communityStats(community),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FollowButton(community: community),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `56 followers · 1 open event`.
String communityStats(Community c) {
  String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
  return '${plural(c.subscriberCount, 'follower')} · '
      '${plural(c.upcomingEvents, 'open event')}';
}
