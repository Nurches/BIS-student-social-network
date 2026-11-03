import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../feed/presentation/feed_controller.dart';
import '../../sync/domain/pending_action.dart';
import '../../sync/presentation/pending_actions_controller.dart';
import '../data/event_repository_provider.dart';
import '../domain/event.dart';
import '../domain/registration_result.dart';

class EventDetailState {
  const EventDetailState({
    required this.event,
    this.busy = false,
    this.message,
    this.offline = false,
  });

  /// Always the latest answer of `GET /events/{id}` (brief §9, "Stale list").
  final Event event;

  /// A request is in flight: the button shows progress and ignores taps.
  final bool busy;

  /// One-off text for a snackbar after an action.
  final String? message;

  /// The last request did not reach the server.
  final bool offline;

  EventDetailState copyWith({
    Event? event,
    bool? busy,
    String? message,
    bool? offline,
  }) => EventDetailState(
    event: event ?? this.event,
    busy: busy ?? this.busy,
    message: message,
    offline: offline ?? this.offline,
  );
}

final eventDetailProvider = AsyncNotifierProvider.autoDispose
    .family<EventDetailController, EventDetailState, int>(
      EventDetailController.new,
      retry: (_, _) => null,
    );

/// The detail screen of one event. The client never decides whether a
/// registration succeeds: it sends the tap and shows the server's answer.
class EventDetailController extends AsyncNotifier<EventDetailState> {
  EventDetailController(this.eventId);

  final int eventId;

  @override
  Future<EventDetailState> build() async =>
      EventDetailState(event: await _fetch());

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    try {
      await ref.read(pendingActionsProvider.notifier).flush();
      final event = await _fetch();
      if (ref.mounted) {
        state = AsyncData(current.copyWith(event: event, offline: false));
      }
    } on NetworkException {
      if (ref.mounted) state = AsyncData(current.copyWith(offline: true));
    }
  }

  Future<void> register() => _act(PendingKind.register);

  Future<void> cancel() => _act(PendingKind.cancel);

  /// Drops a tap that is still waiting in the offline queue.
  Future<void> undoPending() async {
    await ref.read(pendingActionsProvider.notifier).remove(eventId);
    final current = state.value;
    if (current != null && ref.mounted) {
      state = AsyncData(current.copyWith(message: 'Saved action removed.'));
    }
  }

  Future<void> _act(PendingKind kind) async {
    final current = state.value;
    if (current == null || current.busy) return;
    state = AsyncData(current.copyWith(busy: true));

    final repository = ref.read(eventRepositoryProvider);
    String message;
    try {
      message = switch (kind) {
        PendingKind.register => _registrationMessage(
          await repository.register(eventId),
        ),
        PendingKind.cancel => _cancelMessage(
          await repository.cancelRegistration(eventId),
        ),
      };
    } on NetworkException {
      // Brief §9, "Low battery / app killed": keep the tap and send it later.
      await ref
          .read(pendingActionsProvider.notifier)
          .enqueue(
            PendingAction(
              eventId: eventId,
              kind: kind,
              eventTitle: current.event.title,
              queuedAt: DateTime.now(),
            ),
          );
      if (ref.mounted) {
        state = AsyncData(
          current.copyWith(
            busy: false,
            offline: true,
            message:
                'No connection to the server. Saved — it will be sent '
                'as soon as the server is reachable.',
          ),
        );
      }
      return;
    } on NotFoundException {
      if (ref.mounted) {
        state = AsyncError(
          'This event is no longer published.',
          StackTrace.current,
        );
      }
      return;
    } on ApiException {
      if (ref.mounted) {
        state = AsyncData(
          current.copyWith(
            busy: false,
            message: 'Something went wrong on the server. Please try again.',
          ),
        );
      }
      return;
    }

    // The server is right about free places: show its numbers, not ours.
    Event event = current.event;
    try {
      event = await _fetch();
    } on ApiException {
      // Keep the old numbers; the message already says what happened.
    }
    if (ref.mounted) {
      state = AsyncData(EventDetailState(event: event, message: message));
    }
  }

  Future<Event> _fetch() async {
    final event = await ref.read(eventRepositoryProvider).fetchEvent(eventId);
    // Keep the feed card in step, without loading the feed just for this.
    if (ref.mounted && ref.exists(feedControllerProvider)) {
      ref.read(feedControllerProvider.notifier).replaceEvent(event);
    }
    return event;
  }

  static String _registrationMessage(RegistrationResult result) =>
      switch (result) {
        RegistrationConfirmed() => "You're registered.",
        // Brief §9, "Race on the last place": a calm, normal outcome.
        RegistrationWaitListed(:final position) =>
          'The event is full. You are number $position on the waiting '
              'list — you get a notification if a place frees up.',
        RegistrationAlreadyExists() => 'You are already registered.',
        RegistrationClosed() => 'Registration for this event is closed.',
      };

  static String _cancelMessage(CancelResult result) => switch (result) {
    CancelSucceeded() => 'Registration cancelled.',
    CancelNotRegistered() => 'You were not registered for this event.',
    CancelEventStarted() =>
      'The event has already started; it can no longer be cancelled.',
  };
}
