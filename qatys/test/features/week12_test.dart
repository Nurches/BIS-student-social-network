// Week 12: community requests, cancelled and moved events, announcement
// cards on the home screen, and the HTTP side of the v4 contract.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/features/community/data/http_community_repository.dart';
import 'package:qatys/features/community/domain/community.dart';
import 'package:qatys/features/community/presentation/community_request_screen.dart';
import 'package:qatys/features/event/data/event_json.dart';
import 'package:qatys/features/event/data/http_event_repository.dart';
import 'package:qatys/features/event/data/mock_event_repository.dart';
import 'package:qatys/features/event/domain/event.dart';
import 'package:qatys/features/event/domain/registration_result.dart';
import 'package:qatys/features/event/presentation/event_detail_screen.dart';
import 'package:qatys/features/feed/presentation/announcements.dart';
import 'package:qatys/features/inbox/data/http_notification_repository.dart';
import 'package:qatys/features/inbox/domain/app_notification.dart';
import 'package:qatys/features/inbox/presentation/inbox_screen.dart';

import '../helpers/test_app.dart';

const _event = {
  'event_id': 7,
  'community_id': 4,
  'community_name': 'Sports Club',
  'title': 'Futsal cup',
  'description': null,
  'location': 'Sports hall',
  'starts_at': '2026-11-22T17:00:00+05:00',
  'registration_deadline': '2026-11-18T18:00:00+05:00',
  'participant_limit': 40,
  'free_places': 36,
  'my_status': 'confirmed',
  'waiting_position': null,
  'status': 'published',
  'previous_starts_at': '2026-11-20T17:00:00+05:00',
  'cancelled_at': null,
};

void main() {
  group('mock server', () {
    late DateTime now;
    late MockEventRepository server;

    setUp(() {
      now = DateTime(2026, 10, 1, 12);
      server = MockEventRepository(clock: () => now, latency: Duration.zero);
    });

    test('a request is pending, the name is unique, at most 3 wait', () async {
      final sent = await server.requestCommunity(name: ' Chess Club ');
      expect(sent, isA<CommunityRequestSent>());
      expect(
        (sent as CommunityRequestSent).request.status,
        CommunityStatus.pending,
      );
      expect(
        await server.requestCommunity(name: 'chess club'),
        isA<CommunityNameTaken>(),
      );
      expect(
        await server.requestCommunity(name: 'it club'),
        isA<CommunityNameTaken>(),
      );
      await server.requestCommunity(name: 'Robotics');
      await server.requestCommunity(name: 'Book Club');
      expect(
        await server.requestCommunity(name: 'Anime Club'),
        isA<CommunityRequestLimitReached>(),
      );

      final mine = await server.fetchMyRequests();
      expect(mine.pendingCount, 3);
      expect(mine.canRequestMore, isFalse);
      // Another student's request (Debate Society) is not in Explore.
      final names = (await server.fetchCommunities()).map((c) => c.name);
      expect(names, isNot(contains('Debate Society')));
      expect(names, contains('Chess Club'));
    });

    test('approval adds the community_approved notification', () async {
      final sent =
          await server.requestCommunity(name: 'Chess Club')
              as CommunityRequestSent;

      server.approveRequest(sent.request.id);

      final inbox = await server.fetchInbox();
      expect(inbox.items.first.kind, NotificationKind.communityApproved);
      expect(inbox.items.first.eventId, isNull);
      expect(inbox.items.first.communityId, sent.request.id);
      final mine = await server.fetchMyRequests();
      expect(mine.items.single.status, CommunityStatus.confirmed);
    });

    test(
      'a cancelled event stays in My events and refuses registration',
      () async {
        await server.register(1);

        server.cancelByOrganiser(1);

        final event = await server.fetchEvent(1);
        expect(event.isCancelled, isTrue);
        expect(await server.register(1), isA<RegistrationEventCancelled>());
        expect(await server.cancelRegistration(1), isA<CancelEventCancelled>());
        expect((await server.fetchMyEvents()).single.isCancelled, isTrue);
        expect(
          (await server.fetchFeed()).items.map((e) => e.id),
          isNot(contains(1)),
        );
        expect(
          (await server.fetchAnnouncements()).map((e) => e.id),
          isNot(contains(1)),
        );
        expect(
          (await server.fetchInbox()).items.first.kind,
          NotificationKind.eventCancelled,
        );
      },
    );

    test('a moved event keeps the old start time', () async {
      await server.register(2);
      final before = (await server.fetchEvent(2)).startsAt;

      server.rescheduleByOrganiser(2, before.add(const Duration(days: 2)));

      final event = await server.fetchEvent(2);
      expect(event.previousStartsAt, before);
      expect(event.isRescheduled, isTrue);
      expect(
        (await server.fetchInbox()).items.first.kind,
        NotificationKind.eventRescheduled,
      );
    });

    test('announcements: open events of every confirmed community', () async {
      final ids = (await server.fetchAnnouncements()).map((e) => e.id);
      // 7 Futsal cup and 8 Clean-up are from unfollowed communities.
      expect(ids, containsAll([6, 5, 8, 7, 2, 1]));
      expect(ids, isNot(contains(3))); // deadline passed
    });
  });

  group('HTTP, schema v4', () {
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

    test('the Event object reads status and the old start time', () {
      final event = eventFromJson(_event);
      expect(event.status, EventStatus.published);
      expect(
        event.previousStartsAt!.isAtSameMomentAs(
          DateTime.parse('2026-11-20T12:00:00Z'),
        ),
        isTrue,
      );
      // An older cached feed without the v4 fields still parses.
      final old = Map<String, Object?>.of(_event)
        ..remove('status')
        ..remove('previous_starts_at')
        ..remove('cancelled_at');
      expect(eventFromJson(old).isCancelled, isFalse);
      // The cache writes what it reads.
      expect(eventToJson(event)['status'], 'published');
    });

    test('GET /events/announcements', () async {
      final repo = HttpEventRepository(
        answering(200, {
          'items': [_event],
        }),
      );
      final items = await repo.fetchAnnouncements();
      expect(requests.single.url.path, '/api/v1/events/announcements');
      expect(items.single.title, 'Futsal cup');
    });

    test('409 event_cancelled on register and cancel', () async {
      final register = HttpEventRepository(
        answering(409, {'error': 'event_cancelled'}),
      );
      expect(await register.register(7), isA<RegistrationEventCancelled>());
      expect(await register.cancelRegistration(7), isA<CancelEventCancelled>());
      final taken = HttpEventRepository(
        answering(409, {'error': 'already_registered'}),
      );
      expect(await taken.register(7), isA<RegistrationAlreadyExists>());
    });

    test('POST /communities: 201, name taken, limit', () async {
      final created = HttpCommunityRepository(
        answering(201, {
          'community_id': 9,
          'name': 'Chess Club',
          'description': null,
          'status': 'pending',
          'reject_reason': null,
          'created_at': '2026-11-17T10:00:00+00:00',
          'reviewed_at': null,
        }),
      );
      final result = await created.requestCommunity(name: 'Chess Club');
      expect(requests.single.method, 'POST');
      expect(jsonDecode(requests.single.body), {
        'name': 'Chess Club',
        'description': null,
      });
      expect(
        (result as CommunityRequestSent).request.status,
        CommunityStatus.pending,
      );

      expect(
        await HttpCommunityRepository(
          answering(409, {'error': 'community_name_taken'}),
        ).requestCommunity(name: 'IT Club'),
        isA<CommunityNameTaken>(),
      );
      expect(
        await HttpCommunityRepository(
          answering(409, {'error': 'too_many_pending_requests'}),
        ).requestCommunity(name: 'Four'),
        isA<CommunityRequestLimitReached>(),
      );
    });

    test('GET /me/community-requests with a rejection reason', () async {
      final repo = HttpCommunityRepository(
        answering(200, {
          'items': [
            {
              'community_id': 9,
              'name': 'Chess Club',
              'description': 'Blitz',
              'status': 'rejected',
              'reject_reason': 'Join the Games Club',
              'created_at': '2026-11-17T10:00:00+00:00',
              'reviewed_at': '2026-11-17T11:00:00+00:00',
            },
          ],
          'pending_limit': 3,
        }),
      );
      final mine = await repo.fetchMyRequests();
      expect(mine.items.single.rejectReason, 'Join the Games Club');
      expect(mine.canRequestMore, isTrue);
    });

    test('the inbox reads the three new kinds', () {
      final inbox = inboxFromJson({
        'items': [
          {
            'notification_id': 3,
            'kind': 'community_approved',
            'event_id': null,
            'community_id': 9,
            'event_title': null,
            'community_name': 'Chess Club',
            'starts_at': null,
            'previous_starts_at': null,
            'created_at': '2026-11-17T10:00:00+00:00',
            'is_read': false,
          },
          {
            'notification_id': 2,
            'kind': 'event_rescheduled',
            'event_id': 7,
            'community_id': 4,
            'event_title': 'Futsal cup',
            'community_name': 'Sports Club',
            'starts_at': '2026-11-22T12:00:00+00:00',
            'previous_starts_at': '2026-11-20T12:00:00+00:00',
            'created_at': '2026-11-17T09:00:00+00:00',
            'is_read': true,
          },
          {
            'notification_id': 1,
            'kind': 'event_cancelled',
            'event_id': 8,
            'community_id': 5,
            'event_title': 'Clean-up',
            'community_name': 'Volunteer Hub',
            'starts_at': '2026-11-21T12:00:00+00:00',
            'previous_starts_at': null,
            'created_at': '2026-11-17T08:00:00+00:00',
            'is_read': true,
          },
        ],
        'unread_count': 1,
      });
      expect(inbox.items.map((n) => n.kind), [
        NotificationKind.communityApproved,
        NotificationKind.eventRescheduled,
        NotificationKind.eventCancelled,
      ]);
      expect(inbox.items.first.communityId, 9);
    });
  });

  group('screens', () {
    testWidgets(
      'the home screen shows announcement cards that open the event',
      (tester) async {
        await TestApp().pump(tester);

        expect(find.text('Announcements'), findsOneWidget);
        expect(find.byType(AnnouncementCard), findsWidgets);
        // The soonest deadline first: the Flutter workshop (6 hours left).
        final first = find.byType(AnnouncementCard).first;
        expect(
          find.descendant(of: first, matching: find.text('Flutter workshop')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: first, matching: find.text('1 place left')),
          findsOneWidget,
        );

        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(find.byType(EventDetailScreen), findsOneWidget);
        expect(
          find.text('Build and ship your first mobile app in two hours'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a cancelled event says so and offers no registration', (
      tester,
    ) async {
      final app = TestApp();
      await tester.runAsync(() => app.events.inner.register(1));
      app.events.inner.cancelByOrganiser(1);
      await openEvent(tester, 1, app: app);

      expect(find.byKey(const ValueKey('cancelled-notice')), findsOneWidget);
      expect(button('Register'), findsNothing);
      expect(button('Cancel registration'), findsNothing);
      expect(
        find.text('Event cancelled · your place is released'),
        findsOneWidget,
      );
    });

    testWidgets('a moved event shows the new and the old time', (tester) async {
      final app = TestApp();
      final event = (await tester.runAsync(
        () => app.events.inner.fetchEvent(2),
      ))!;
      app.events.inner.rescheduleByOrganiser(
        2,
        event.startsAt.add(const Duration(days: 1)),
      );
      await openEvent(tester, 2, app: app);

      expect(find.byKey(const ValueKey('moved-notice')), findsOneWidget);
      expect(find.textContaining('(was '), findsOneWidget);
      expect(button('Register'), findsOneWidget);
    });

    testWidgets('Explore: request a community, then see it in review', (
      tester,
    ) async {
      await TestApp().pump(tester);
      await openTab(tester, 'Explore');

      await tester.tap(find.text('Request a community'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityRequestScreen), findsOneWidget);
      expect(find.text('How it works'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'ab');
      await tester.tap(find.text('Send to the Student Union'));
      await tester.pumpAndSettle();
      expect(find.text('At least 3 characters.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'IT Club');
      await tester.tap(find.text('Send to the Student Union'));
      await tester.pumpAndSettle();
      expect(
        find.text('A community with this name already exists.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField).first, 'Chess Club');
      await tester.tap(find.text('Send to the Student Union'));
      await tester.pumpAndSettle();

      expect(find.byType(CommunityRequestScreen), findsNothing);
      expect(
        find.text(
          'Request for "Chess Club" sent. The Student Union will review it.',
        ),
        findsOneWidget,
      );
      expect(find.text('My requests (1)'), findsOneWidget);
      expect(find.text('Chess Club'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
    });

    testWidgets('inbox: an approved request and a cancelled event', (
      tester,
    ) async {
      final app = TestApp();
      final sent =
          (await tester.runAsync(
                () => app.events.inner.requestCommunity(name: 'Chess Club'),
              ))!
              as CommunityRequestSent;
      app.events.inner.approveRequest(sent.request.id);
      await tester.runAsync(() => app.events.inner.register(1));
      app.events.inner.cancelByOrganiser(1);
      await app.pump(tester);

      await tester.tap(find.byTooltip('Notifications, 3 new'));
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
      expect(
        find.text('Approved: Chess Club is now a community'),
        findsOneWidget,
      );
      expect(find.text('Cancelled: Autumn Hackathon 2026'), findsOneWidget);
    });
  });
}

// From event_detail_screen_test.dart, so this file stands alone.
Future<TestApp> openEvent(
  WidgetTester tester,
  int eventId, {
  TestApp? app,
}) async {
  app ??= TestApp();
  await app.pump(tester);
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  // ignore: unawaited_futures
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => EventDetailScreen(eventId: eventId),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

Finder button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);
