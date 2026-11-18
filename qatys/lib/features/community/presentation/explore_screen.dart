import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/ui.dart';
import '../domain/community.dart';
import 'communities_controller.dart';
import 'community_request_screen.dart';
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

  /// The name of the request just sent, for the confirmation notice.
  String? _sent;

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
            onPressed: () {
              ref.invalidate(myCommunityRequestsProvider);
              controller.refresh();
            },
          ),
        ],
      ),
      // Week 12: any student can ask for a community.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'request-community',
        onPressed: () async {
          final sent = await Navigator.of(context).push<CommunityRequest>(
            MaterialPageRoute<CommunityRequest>(
              builder: (_) => const CommunityRequestScreen(),
            ),
          );
          // A notice in the list, not a snackbar: a snackbar shown during
          // the page transition would be duplicated on every tab's Scaffold.
          if (sent != null && mounted) setState(() => _sent = sent.name);
        },
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Request a community'),
      ),
      body: switch (communities) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(myCommunityRequestsProvider);
            return controller.refresh();
          },
          child: _List(
            communities: value,
            sent: _sent,
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

class _List extends ConsumerWidget {
  const _List({
    required this.communities,
    required this.query,
    required this.onQuery,
    this.sent,
  });

  final List<Community> communities;
  final String? sent;
  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests =
        ref.watch(myCommunityRequestsProvider).value?.items ?? const [];
    final q = query.trim().toLowerCase();
    final matching = communities
        .where(
          (c) =>
              // The student's own requests are listed under "My requests".
              !c.isPending &&
              (q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  c.description.toLowerCase().contains(q)),
        )
        .toList();
    final following = matching.where((c) => c.isSubscribed).toList();
    final others = matching.where((c) => !c.isSubscribed).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Room for the floating "Request a community" button.
      padding: const EdgeInsets.only(bottom: 96),
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
        if (sent case final name?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDF3E4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF14532D)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Request for "$name" sent. The Student Union will '
                        'review it.',
                        style: const TextStyle(
                          color: Color(0xFF14532D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (requests.isNotEmpty && q.isEmpty) ...[
          SectionTitle('My requests (${requests.length})'),
          for (final r in requests) CommunityRequestTile(request: r),
        ],
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
