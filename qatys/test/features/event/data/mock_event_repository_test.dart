import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/core/network/api_exception.dart';
import 'package:qatys/features/event/data/mock_event_repository.dart';
import 'package:qatys/features/event/domain/event.dart';
import 'package:qatys/features/event/domain/registration_result.dart';

void main() {
  late DateTime now;
  late MockEventRepository repository;

  setUp(() {
    now = DateTime(2026, 10, 1, 12);
    repository = MockEventRepository(clock: () => now, latency: Duration.zero);
  });

  test('feed hides passed deadlines and is ordered by deadline', () async {
    final page = await repository.fetchFeed();

    expect(page.items.map((e) => e.id), [6, 5, 2, 1]);
    expect(page.nextCursor, isNull);
  });

  test('feed pages with a cursor', () async {
    final first = await repository.fetchFeed(limit: 3);
    final second = await repository.fetchFeed(
      limit: 3,
      cursor: first.nextCursor,
    );

    expect(first.items, hasLength(3));
    expect(second.items.map((e) => e.id), [1]);
    expect(second.nextCursor, isNull);
  });

  test('registration with free places is confirmed', () async {
    final result = await repository.register(1);
    final event = await repository.fetchEvent(1);

    expect(result, isA<RegistrationConfirmed>());
    expect(event.myState, RegistrationState.registered);
    expect(event.freePlaces, 26);
  });

  test('registration on a full event joins the waiting list', () async {
    final result = await repository.register(5);
    final event = await repository.fetchEvent(5);

    expect(result, isA<RegistrationWaitListed>());
    expect((result as RegistrationWaitListed).position, 3);
    expect(event.myState, RegistrationState.waitingList);
    expect(event.waitingPosition, 3);
    expect(event.freePlaces, 0);
  });

  test('registration after the deadline is closed', () async {
    expect(await repository.register(3), isA<RegistrationClosed>());
  });

  test('a second registration is rejected', () async {
    await repository.register(1);
    expect(await repository.register(1), isA<RegistrationAlreadyExists>());
  });

  test('losing the race on the last place lands on the waiting list', () async {
    repository.takePlaceByAnotherStudent(6);

    final result = await repository.register(6);

    expect(result, isA<RegistrationWaitListed>());
  });

  test('cancelling frees the place and promotes the waiting list', () async {
    await repository.register(6);
    repository.takePlaceByAnotherStudent(6); // full, goes to the waiting list

    expect(await repository.cancelRegistration(6), isA<CancelSucceeded>());
    final event = await repository.fetchEvent(6);

    expect(event.myState, RegistrationState.none);
    expect(event.freePlaces, 0, reason: 'the waiting student took the place');
  });

  test('cancelling without a registration is a calm answer', () async {
    expect(await repository.cancelRegistration(1), isA<CancelNotRegistered>());
  });

  test('unknown event throws', () {
    expect(repository.fetchEvent(404), throwsA(isA<NotFoundException>()));
  });
}
