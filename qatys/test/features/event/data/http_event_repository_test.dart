import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/core/network/api_exception.dart';
import 'package:qatys/features/event/data/http_event_repository.dart';
import 'package:qatys/features/event/domain/event.dart';
import 'package:qatys/features/event/domain/registration_result.dart';

const _baseUrl = 'https://api.test/api/v1';

const _eventJson = {
  'event_id': 1,
  'community_id': 1,
  'community_name': 'IT Club',
  'title': 'Autumn Hackathon 2026',
  'description': '24-hour team hackathon',
  'location': 'Block C, room 301',
  'starts_at': '2026-10-08T10:00:00+05:00',
  'registration_deadline': '2026-10-04T23:59:00+05:00',
  'participant_limit': 30,
  'free_places': 27,
  'my_status': 'waiting_list',
  'waiting_position': 2,
};

void main() {
  late List<http.Request> requests;

  HttpEventRepository repositoryAnswering(
    int status, [
    Object? body,
    String? rawBody,
  ]) {
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        rawBody ?? (body == null ? '' : jsonEncode(body)),
        status,
      );
    });
    return HttpEventRepository(
      ApiClient(
        baseUrl: _baseUrl,
        readToken: () async => 'jwt-token',
        httpClient: client,
      ),
    );
  }

  setUp(() => requests = []);

  test('feed request and parsing', () async {
    final repository = repositoryAnswering(200, {
      'items': [_eventJson],
      'next_cursor': 17,
    });

    final page = await repository.fetchFeed(limit: 10, cursor: '5');

    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.toString(), '$_baseUrl/feed?limit=10&cursor=5');
    expect(request.headers['Authorization'], 'Bearer jwt-token');

    final event = page.items.single;
    expect(event.title, 'Autumn Hackathon 2026');
    expect(event.freePlaces, 27);
    expect(event.myState, RegistrationState.waitingList);
    expect(event.waitingPosition, 2);
    expect(
      event.startsAt.isAtSameMomentAs(DateTime.utc(2026, 10, 8, 5)),
      isTrue,
    );
    expect(page.nextCursor, '17');
  });

  test('first feed page sends no cursor', () async {
    final repository = repositoryAnswering(200, {'items': <Object>[]});

    await repository.fetchFeed();

    expect(requests.single.url.queryParameters, {'limit': '20'});
  });

  group('register maps docs/api.md answers', () {
    Future<RegistrationResult> registerWith(int status, [Object? body]) =>
        repositoryAnswering(status, body).register(1);

    test('201 confirmed', () async {
      expect(
        await registerWith(201, {'status': 'confirmed', 'registration_id': 42}),
        isA<RegistrationConfirmed>(),
      );
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/v1/events/1/registrations');
    });

    test('200 waiting list', () async {
      final result = await registerWith(200, {
        'status': 'waiting_list',
        'position': 3,
      });
      expect((result as RegistrationWaitListed).position, 3);
    });

    test('409 already registered', () async {
      expect(
        await registerWith(409, {'error': 'already_registered'}),
        isA<RegistrationAlreadyExists>(),
      );
    });

    test('410 deadline passed', () async {
      expect(
        await registerWith(410, {'error': 'deadline_passed'}),
        isA<RegistrationClosed>(),
      );
    });
  });

  test('401 throws UnauthorizedException', () {
    expect(
      repositoryAnswering(401, {'error': 'unauthorized'}).fetchEvent(1),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('captive-portal HTML is treated as no connection', () {
    expect(
      repositoryAnswering(200, null, '<html>Wi-Fi login</html>').fetchEvent(1),
      throwsA(isA<NetworkException>()),
    );
  });

  test('a body that breaks the contract is reported, not crashed on', () {
    expect(
      repositoryAnswering(200, {'event_id': 'one'}).fetchEvent(1),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });

  test('cancel sends DELETE', () async {
    final result = await repositoryAnswering(200, {
      'status': 'cancelled',
    }).cancelRegistration(1);

    expect(result, isA<CancelSucceeded>());
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v1/events/1/registrations');
  });

  test('cancel answers map to calm results (docs/api.md)', () async {
    expect(
      await repositoryAnswering(404, {
        'error': 'not_registered',
      }).cancelRegistration(1),
      isA<CancelNotRegistered>(),
    );
    expect(
      await repositoryAnswering(410, {
        'error': 'event_started',
      }).cancelRegistration(1),
      isA<CancelEventStarted>(),
    );
    expect(
      repositoryAnswering(404, {
        'error': 'event_not_found',
      }).cancelRegistration(1),
      throwsA(isA<NotFoundException>()),
    );
  });
}
