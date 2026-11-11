// MVP extension: the HTTP side of communities, my events, the inbox and
// sign-up follows docs/api.md.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/core/network/api_exception.dart';
import 'package:qatys/features/auth/data/http_auth_repository.dart';
import 'package:qatys/features/auth/domain/register_result.dart';
import 'package:qatys/features/community/data/http_community_repository.dart';
import 'package:qatys/features/event/data/http_event_repository.dart';
import 'package:qatys/features/inbox/data/http_notification_repository.dart';
import 'package:qatys/features/inbox/domain/app_notification.dart';

const _event = {
  'event_id': 7,
  'community_id': 4,
  'community_name': 'Sports Club',
  'title': 'Futsal cup',
  'description': null,
  'location': 'Sports hall',
  'starts_at': '2026-11-20T17:00:00+05:00',
  'registration_deadline': '2026-11-18T18:00:00+05:00',
  'participant_limit': 40,
  'free_places': 36,
  'my_status': null,
  'waiting_position': null,
};

void main() {
  late List<http.Request> requests;

  ApiClient answering(int status, [Object? body]) {
    requests = [];
    return ApiClient(
      baseUrl: 'https://api.test/api/v1',
      readToken: () async => 'token',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(body == null ? '' : jsonEncode(body), status);
      }),
    );
  }

  test('GET /communities is parsed with the follow state', () async {
    final repo = HttpCommunityRepository(
      answering(200, [
        {
          'community_id': 4,
          'name': 'Sports Club',
          'description': null,
          'is_confirmed': true,
          'subscriber_count': 2,
          'upcoming_events': 1,
          'is_subscribed': false,
        },
      ]),
    );

    final list = await repo.fetchCommunities();

    expect(requests.single.url.path, '/api/v1/communities');
    expect(requests.single.headers['Authorization'], 'Bearer token');
    expect(list.single.name, 'Sports Club');
    expect(list.single.description, '');
    expect(list.single.isSubscribed, isFalse);
  });

  test('follow is PUT, unfollow is DELETE, 404 is NotFoundException', () async {
    await HttpCommunityRepository(
      answering(204),
    ).setSubscribed(4, subscribed: true);
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v1/communities/4/subscription');

    await HttpCommunityRepository(
      answering(204),
    ).setSubscribed(4, subscribed: false);
    expect(requests.single.method, 'DELETE');

    expect(
      HttpCommunityRepository(
        answering(404, {'error': 'community_not_found'}),
      ).setSubscribed(9, subscribed: true),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('community events and my events come as { items: [...] }', () async {
    final events = await HttpCommunityRepository(
      answering(200, {
        'items': [_event],
      }),
    ).fetchCommunityEvents(4);
    expect(requests.single.url.path, '/api/v1/communities/4/events');
    expect(events.single.title, 'Futsal cup');

    final mine = await HttpEventRepository(
      answering(200, {
        'items': [_event],
      }),
    ).fetchMyEvents();
    expect(requests.single.url.path, '/api/v1/me/registrations');
    expect(mine.single.freePlaces, 36);
  });

  test('the inbox is parsed and "mark all read" is a POST', () async {
    final inbox = await HttpNotificationRepository(
      answering(200, {
        'items': [
          {
            'notification_id': 3,
            'kind': 'waiting_list_promoted',
            'event_id': 7,
            'event_title': 'Futsal cup',
            'community_name': 'Sports Club',
            'created_at': '2026-11-11T08:00:00+00:00',
            'is_read': false,
          },
        ],
        'unread_count': 1,
      }),
    ).fetchInbox();
    expect(requests.single.url.path, '/api/v1/me/notifications');
    expect(inbox.unreadCount, 1);
    expect(inbox.items.single.kind, NotificationKind.waitingListPromoted);
    expect(inbox.items.single.createdAt.isUtc, isFalse); // shown in phone time

    await HttpNotificationRepository(answering(204)).markAllRead();
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v1/me/notifications/read');
  });

  test('register maps every documented answer', () async {
    Future<RegisterResult> register(int status, [Object? body]) =>
        HttpAuthRepository(answering(status, body)).register(
          email: 'new@kbtu.kz',
          password: 'long-enough',
          fullName: 'New Student',
        );

    expect(await register(201, {'student_id': 1}), isA<RegisterCreated>());
    expect(jsonDecode(requests.single.body), {
      'email': 'new@kbtu.kz',
      'password': 'long-enough',
      'full_name': 'New Student',
    });
    expect(requests.single.headers['Authorization'], isNull);
    expect(
      await register(409, {'error': 'email_already_registered'}),
      isA<RegisterEmailTaken>(),
    );
    expect(
      await register(422, {'error': 'not_a_university_email'}),
      isA<RegisterNotUniversityEmail>(),
    );
    expect(
      await register(422, {'error': 'password_too_short'}),
      isA<RegisterBadPassword>().having((r) => r.tooShort, 'tooShort', true),
    );
    expect(
      register(422, {'error': 'validation_failed'}),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });
}
