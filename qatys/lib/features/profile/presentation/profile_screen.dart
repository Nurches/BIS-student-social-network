import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/session_controller.dart';
import '../../community/presentation/communities_controller.dart';
import '../../event/domain/event.dart';
import '../../event/presentation/my_events_controller.dart';
import '../../feed/presentation/feed_controller.dart';
import '../../push/domain/push_service.dart';

const appVersion = '1.0.0';

/// Profile tab: who is signed in, a few numbers, notifications and logout.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(sessionControllerProvider).value?.student;
    final now = ref.watch(clockProvider)();
    final myEvents = ref.watch(myEventsProvider).value ?? const [];
    final following = (ref.watch(communitiesProvider).value ?? const [])
        .where((c) => c.isSubscribed)
        .length;
    final upcoming = myEvents.where((e) => e.startsAt.isAfter(now));
    final registered = upcoming
        .where((e) => e.myState == RegistrationState.registered)
        .length;
    final waiting = upcoming
        .where((e) => e.myState == RegistrationState.waitingList)
        .length;

    Future<void> logout() =>
        ref.read(sessionControllerProvider.notifier).logout();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: logout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Header(name: student?.fullName ?? '', email: student?.email ?? ''),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(value: registered, label: 'Registered'),
              const SizedBox(width: 10),
              _Stat(value: waiting, label: 'Waiting list'),
              const SizedBox(width: 10),
              _Stat(value: following, label: 'Following'),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                const _NotificationsTile(),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: const Text('How Qatys works'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showHowItWorks(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About Qatys'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Qatys',
                    applicationVersion: appVersion,
                    applicationIcon: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/icon/qatys_logo.png',
                        width: 48,
                        height: 48,
                      ),
                    ),
                    children: const [
                      Text(
                        'All KBTU events in one feed, with a notification '
                        'the moment they are published. Semester project of '
                        'the course Basics of Information Systems, Fall 2026.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.urgent),
              title: const Text(
                'Sign out of this phone',
                style: TextStyle(
                  color: AppTheme.urgent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                'Removes your account, saved events and notifications from '
                'this phone.',
              ),
              onTap: logout,
            ),
          ),
        ],
      ),
    );
  }

  void _showHowItWorks(BuildContext context) {
    const steps = [
      (Icons.explore_outlined, 'Follow the clubs and offices you care about.'),
      (
        Icons.notifications_active_outlined,
        'Get a notification the moment they publish an event.',
      ),
      (
        Icons.how_to_reg_outlined,
        'Register in one tap. If it is full, join the waiting list.',
      ),
      (
        Icons.celebration_outlined,
        'Someone cancels? The first on the waiting list gets the place '
            'and a notification.',
      ),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How Qatys works',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final (icon, text) in steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(icon, color: AppTheme.brand),
                      const SizedBox(width: 16),
                      Expanded(child: Text(text)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Text(
              initials(name),
              style: const TextStyle(
                color: AppTheme.brand,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(email, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(
                '$value',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows whether pushes are allowed and asks for the permission when not.
class _NotificationsTile extends ConsumerStatefulWidget {
  const _NotificationsTile();

  @override
  ConsumerState<_NotificationsTile> createState() => _NotificationsTileState();
}

class _NotificationsTileState extends ConsumerState<_NotificationsTile> {
  late Future<bool> _permitted = ref.read(pushServiceProvider).isPermitted();

  @override
  Widget build(BuildContext context) {
    final push = ref.watch(pushServiceProvider);
    return FutureBuilder<bool>(
      future: _permitted,
      builder: (context, snapshot) {
        final on = snapshot.data ?? false;
        final subtitle = !push.isAvailable
            ? 'Not available in this build'
            : on
            ? 'On: you get a notification for every new event'
            : 'Off: tap to turn on';
        return ListTile(
          leading: Icon(
            on
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
          ),
          title: const Text('Notifications'),
          subtitle: Text(subtitle),
          onTap: !push.isAvailable || on
              ? null
              : () => setState(() => _permitted = push.requestPermission()),
        );
      },
    );
  }
}
