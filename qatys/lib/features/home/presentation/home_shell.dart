import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../community/presentation/explore_screen.dart';
import '../../event/presentation/my_events_controller.dart';
import '../../event/presentation/my_events_screen.dart';
import '../../feed/presentation/feed_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import 'home_tab_controller.dart';

/// The signed-in app: four tabs with single-tap navigation (brief §8, "No
/// gesture-only paths"). A tab is built the first time it is opened and then
/// kept, so its scroll position survives switching.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _opened = <HomeTab>{HomeTab.feed};

  static Widget _screen(HomeTab tab) => switch (tab) {
    HomeTab.feed => const FeedScreen(),
    HomeTab.explore => const ExploreScreen(),
    HomeTab.myEvents => const MyEventsScreen(),
    HomeTab.profile => const ProfileScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    _opened.add(tab);

    // No outer Scaffold: each tab is a root Scaffold, so its snackbars sit
    // above the navigation bar instead of under it.
    return Column(
      children: [
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: IndexedStack(
              index: tab.index,
              children: [
                for (final t in HomeTab.values)
                  _opened.contains(t) ? _screen(t) : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        NavigationBar(
          selectedIndex: tab.index,
          onDestinationSelected: (i) {
            final selected = HomeTab.values[i];
            // Registrations change on other screens: always show fresh ones.
            if (selected == HomeTab.myEvents || selected == HomeTab.profile) {
              ref.invalidate(myEventsProvider);
            }
            ref.read(homeTabProvider.notifier).select(selected);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Feed',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.confirmation_number_outlined),
              selectedIcon: Icon(Icons.confirmation_number),
              label: 'My events',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ],
    );
  }
}
