/// Contract test of the real HTTP client against a running server:
///
///   cd server && python seed.py --yes && uvicorn app.main:app --port 8000
///   flutter test test/integration --dart-define=LIVE_API=http://localhost:8000/api/v1
///
/// Skipped without LIVE_API, so the normal suite never needs a server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/core/network/reachability.dart';
import 'package:qatys/features/auth/data/http_auth_repository.dart';
import 'package:qatys/features/auth/domain/login_result.dart';
import 'package:qatys/features/event/data/http_event_repository.dart';
import 'package:qatys/features/event/domain/event.dart';
import 'package:qatys/features/event/domain/registration_result.dart';
import 'package:qatys/features/push/data/device_token_repository.dart';

const _liveApi = String.fromEnvironment('LIVE_API');

void main() {
  String? token;
  ApiClient client() =>
      ApiClient(baseUrl: _liveApi, readToken: () async => token);

  Future<void> signIn(String email) async {
    final result = await HttpAuthRepository(
      client(),
    ).login(email: email, password: 'qatys2026');
    token = (result as LoginSucceeded).session.token;
  }

  test(
    'health, login, feed, detail, register, cancel, device token',
    () async {
      expect(await HealthCheckProbe(client()).isServerReachable(), isTrue);

      expect(
        await HttpAuthRepository(
          client(),
        ).login(email: 'nurassyl@kbtu.kz', password: 'wrong'),
        isA<LoginInvalidCredentials>(),
      );

      await signIn('laila@kbtu.kz');
      final events = HttpEventRepository(client());

      final feed = await events.fetchFeed(limit: 2);
      expect(feed.items, hasLength(2));
      expect(feed.nextCursor, isNotNull);
      final rest = await events.fetchFeed(limit: 2, cursor: feed.nextCursor);
      final ids = [...feed.items, ...rest.items].map((e) => e.id).toSet();
      expect(ids, hasLength(4), reason: 'every open event exactly once');

      final workshop = [
        ...feed.items,
        ...rest.items,
      ].firstWhere((e) => e.title == 'Flutter workshop');
      expect(workshop.freePlaces, 1);
      expect(workshop.startsAt.isUtc, isFalse, reason: 'converted to local');

      expect(await events.register(workshop.id), isA<RegistrationConfirmed>());
      final after = await events.fetchEvent(workshop.id);
      expect(after.myState, RegistrationState.registered);
      expect(after.freePlaces, 0);
      expect(
        await events.register(workshop.id),
        isA<RegistrationAlreadyExists>(),
      );

      // Another student: the event is full now → waiting list, not an error.
      await signIn('madina@kbtu.kz');
      final waiting = await HttpEventRepository(client()).register(workshop.id);
      expect(waiting, isA<RegistrationWaitListed>());

      // The first student cancels → madina is promoted.
      await signIn('laila@kbtu.kz');
      expect(
        await HttpEventRepository(client()).cancelRegistration(workshop.id),
        isA<CancelSucceeded>(),
      );
      expect(
        await HttpEventRepository(client()).cancelRegistration(workshop.id),
        isA<CancelNotRegistered>(),
      );
      await signIn('madina@kbtu.kz');
      final promoted = await HttpEventRepository(
        client(),
      ).fetchEvent(workshop.id);
      expect(promoted.myState, RegistrationState.registered);

      // Closed event: opened from an old push, renders as closed (FR-02).
      final closed = await HttpEventRepository(client()).fetchEvent(5);
      expect(closed.isDeadlinePassed(DateTime.now()), isTrue);
      expect(
        await HttpEventRepository(client()).register(5),
        isA<RegistrationClosed>(),
      );

      final tokens = HttpDeviceTokenRepository(client());
      await tokens.save('integration-test-token');
      await tokens.delete('integration-test-token');
    },
    skip: _liveApi.isEmpty ? 'set --dart-define=LIVE_API=...' : false,
  );
}
