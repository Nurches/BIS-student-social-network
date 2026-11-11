import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';
import '../data/notification_repository_provider.dart';
import '../domain/app_notification.dart';

/// The in-app inbox and the unread badge on the feed.
final inboxProvider = AsyncNotifierProvider<InboxController, Inbox>(
  InboxController.new,
  retry: (_, _) => null,
);

class InboxController extends AsyncNotifier<Inbox> {
  @override
  Future<Inbox> build() async {
    final studentId = ref.watch(
      sessionControllerProvider.select((s) => s.value?.student.id),
    );
    if (studentId == null) return Inbox.empty;
    return ref.read(notificationRepositoryProvider).fetchInbox();
  }

  Future<void> refresh() async {
    final fresh = await ref.read(notificationRepositoryProvider).fetchInbox();
    if (ref.mounted) state = AsyncData(fresh);
  }

  /// The badge goes to zero; the dots stay for this visit of the inbox, so
  /// the student still sees which ones were new.
  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null || current.unreadCount == 0) return;
    await ref.read(notificationRepositoryProvider).markAllRead();
    if (ref.mounted) {
      state = AsyncData(Inbox(items: current.items, unreadCount: 0));
    }
  }
}
