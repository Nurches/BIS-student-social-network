import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/core/network/reachability.dart';
import 'package:qatys/core/storage/local_store.dart';
import 'package:qatys/features/auth/data/auth_providers.dart';
import 'package:qatys/features/event/data/event_repository_provider.dart';
import 'package:qatys/features/event/domain/event.dart';
import 'package:qatys/features/sync/domain/pending_action.dart';
import 'package:qatys/features/sync/presentation/pending_actions_controller.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_app.dart';

void main() {
  late SwitchableEventRepository events;
  late InMemoryStore store;
  late ProviderContainer container;
  late _Probe probe;

  PendingAction action(int eventId, PendingKind kind) => PendingAction(
    eventId: eventId,
    kind: kind,
    eventTitle: 'Event $eventId',
    queuedAt: DateTime(2026, 11, 3),
  );

  ProviderContainer create() => ProviderContainer.test(
    overrides: [
      sessionStorageProvider.overrideWithValue(
        InMemorySessionStorage(
          sessionExpiringAt(DateTime.now().add(const Duration(hours: 1))),
        ),
      ),
      eventRepositoryProvider.overrideWithValue(events),
      localStoreProvider.overrideWithValue(store),
      reachabilityProbeProvider.overrideWithValue(probe),
    ],
  );

  PendingActionsController queue() =>
      container.read(pendingActionsProvider.notifier);

  setUp(() async {
    events = SwitchableEventRepository();
    store = InMemoryStore();
    probe = _Probe();
    container = create();
    // Read before the session is restored: must not hang.
    await container.read(pendingActionsProvider.future);
  });

  test('register then cancel while offline leaves nothing to send', () async {
    await queue().enqueue(action(1, PendingKind.register));
    await queue().enqueue(action(1, PendingKind.cancel));

    expect(container.read(pendingActionsProvider).value, isEmpty);
  });

  test('the same intent twice is kept once', () async {
    await queue().enqueue(action(1, PendingKind.register));
    await queue().enqueue(action(1, PendingKind.register));

    expect(container.read(pendingActionsProvider).value, hasLength(1));
  });

  test('flush stops at the first network failure and keeps the rest', () async {
    await queue().enqueue(action(1, PendingKind.register));
    await queue().enqueue(action(2, PendingKind.register));
    events.offline = true;

    expect(await queue().flush(), 0);
    expect(container.read(pendingActionsProvider).value, hasLength(2));
  });

  test(
    'flush sends everything; the server answer settles each action',
    () async {
      await queue().enqueue(action(1, PendingKind.register));
      await queue().enqueue(action(3, PendingKind.register)); // deadline passed
      await queue().enqueue(action(404, PendingKind.register)); // event gone

      expect(await queue().flush(), 3);
      expect(container.read(pendingActionsProvider).value, isEmpty);
      expect(
        (await events.fetchEvent(1)).myState,
        RegistrationState.registered,
      );
    },
  );

  test('the queue is stored per student and survives a restart', () async {
    await queue().enqueue(action(1, PendingKind.register));

    final restarted = create();
    expect(await restarted.read(pendingActionsProvider.future), hasLength(1));
  });

  test('nothing is sent until GET /health answers (captive portal)', () async {
    await queue().enqueue(action(1, PendingKind.register));
    probe.reachable = false;

    expect(await queue().flush(), 0);
    expect(events.registerCalls, 0);
    expect(container.read(pendingActionsProvider).value, hasLength(1));

    probe.reachable = true;
    expect(await queue().flush(), 1);
    expect(events.registerCalls, 1);
  });
}

class _Probe implements ReachabilityProbe {
  bool reachable = true;

  @override
  Future<bool> isServerReachable() async => reachable;
}
