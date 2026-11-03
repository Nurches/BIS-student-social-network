import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/reachability.dart';
import '../../auth/presentation/session_controller.dart';
import '../../event/data/event_repository_provider.dart';
import '../data/pending_actions_store.dart';
import '../domain/pending_action.dart';

/// Registration taps waiting for the server, oldest first.
final pendingActionsProvider =
    AsyncNotifierProvider<PendingActionsController, List<PendingAction>>(
      PendingActionsController.new,
      retry: (_, _) => null,
    );

class PendingActionsController extends AsyncNotifier<List<PendingAction>> {
  bool _flushing = false;

  int? get _studentId => ref.read(sessionControllerProvider).value?.student.id;

  @override
  Future<List<PendingAction>> build() async {
    // Waits for the restored session instead of answering "empty" while it
    // is still loading (a `.future` read at that moment never completed).
    final session = await ref.watch(sessionControllerProvider.future);
    final studentId = session?.student.id;
    if (studentId == null) return const [];
    return ref.read(pendingActionsStoreProvider).read(studentId);
  }

  PendingAction? forEvent(int eventId) {
    for (final action in state.value ?? const <PendingAction>[]) {
      if (action.eventId == eventId) return action;
    }
    return null;
  }

  /// Keeps only the latest intent per event: "register" then "cancel" while
  /// offline means nothing has to be sent at all.
  Future<void> enqueue(PendingAction action) async {
    final current = [...?state.value];
    final previous = current.indexWhere((a) => a.eventId == action.eventId);
    if (previous >= 0) {
      final cancelsOut = current[previous].kind != action.kind;
      current.removeAt(previous);
      if (!cancelsOut) current.add(action);
    } else {
      current.add(action);
    }
    await _save(current);
  }

  Future<void> remove(int eventId) =>
      _save([...?state.value]..removeWhere((a) => a.eventId == eventId));

  /// Sends every queued action. Stops at the first network failure (the rest
  /// stays queued); any answer from the server, including "already
  /// registered" or "closed", settles the action. Returns how many were sent.
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final queued = await future;
      if (queued.isEmpty) return 0;
      // Brief §9: send only after our own /health answered — never on the
      // phone's "connected" flag, which lies behind a Wi-Fi login page.
      if (!await ref.read(reachabilityProbeProvider).isServerReachable()) {
        return 0;
      }
      final repository = ref.read(eventRepositoryProvider);
      // On a cold start the queue may still be loading from the phone.
      for (final action in [...await future]) {
        try {
          switch (action.kind) {
            case PendingKind.register:
              await repository.register(action.eventId);
            case PendingKind.cancel:
              await repository.cancelRegistration(action.eventId);
          }
        } on NetworkException {
          break;
        } on UnauthorizedException {
          break;
        } on UnexpectedResponseException {
          // A server error: try again later rather than lose the tap.
          break;
        } on NotFoundException {
          // The event is gone: nothing left to send.
        }
        sent++;
        if (!ref.mounted) return sent;
        await remove(action.eventId);
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }

  Future<void> _save(List<PendingAction> actions) async {
    final studentId = _studentId;
    if (studentId == null) return;
    await ref.read(pendingActionsStoreProvider).write(studentId, actions);
    if (ref.mounted) state = AsyncData(List.unmodifiable(actions));
  }
}
