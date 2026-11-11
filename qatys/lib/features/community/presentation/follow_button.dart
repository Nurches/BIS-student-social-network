import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../domain/community.dart';
import 'communities_controller.dart';

/// "Follow" / "Following ✓". The change shows at once and goes back with a
/// message when the server cannot be reached.
class FollowButton extends ConsumerWidget {
  const FollowButton({
    required this.community,
    this.expanded = false,
    super.key,
  });

  final Community community;

  /// Full width on the community screen, compact in the list.
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = community.isSubscribed;
    final size = expanded ? const Size.fromHeight(52) : const Size(112, 48);

    Future<void> toggle() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(communitiesProvider.notifier)
            .setSubscribed(community.id, subscribed: !following);
      } on ApiException catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              e is NetworkException
                  ? 'No connection to the server. Try again.'
                  : 'Could not change it. Try again.',
            ),
          ),
        );
      }
    }

    return following
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: toggle,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Following'),
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: toggle,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Follow'),
          );
  }
}
