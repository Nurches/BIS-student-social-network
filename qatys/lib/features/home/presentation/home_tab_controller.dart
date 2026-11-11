import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';

enum HomeTab { feed, explore, myEvents, profile }

/// The selected bottom tab; back to the feed for every new sign-in.
final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(
  HomeTabController.new,
);

class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() {
    ref.watch(sessionControllerProvider.select((s) => s.value?.student.id));
    return HomeTab.feed;
  }

  void select(HomeTab tab) => state = tab;
}
