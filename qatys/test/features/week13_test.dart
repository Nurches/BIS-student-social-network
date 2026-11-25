// Week 13: posters, the QR ticket, check-in status, feedback after the event,
// and the HTTP side of the v5 contract. Test cases of Madina's run are named
// where the app shows them (TC-16 ticket, TC-18 / TC-19 no rating, TC-21 poster).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qatys/app.dart';
import 'package:qatys/core/config/app_config.dart';
import 'package:qatys/core/network/api_client.dart';
import 'package:qatys/features/event/data/event_json.dart';
import 'package:qatys/features/event/data/http_event_repository.dart';
import 'package:qatys/features/event/data/mock_event_repository.dart';
import 'package:qatys/features/event/domain/feedback_result.dart';
import 'package:qatys/features/event/domain/registration_result.dart';
import 'package:qatys/features/event/domain/ticket.dart';
import 'package:qatys/features/event/presentation/event_detail_screen.dart';
import 'package:qatys/features/event/presentation/poster_image.dart';
import 'package:qatys/features/event/presentation/ticket_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../helpers/test_app.dart';

const _baseUrl = 'https://qatys-api.test/api/v1';

const _v5Event = {
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
  'previous_starts_at': null,
  'cancelled_at': null,
  'ends_at': '2026-11-22T20:00:00+05:00',
  'poster_url': '/api/v1/events/7/poster?v=1763820000000',
  'checked_in_at': '2026-11-22T16:52:00+05:00',
  'my_rating': null,
  'feedback_open': true,
};

const _ticket = {
  'event_id': 7,
  'registration_id': 31,
  'code': 'K7Q2XM',
  'qr': 'QATYS-T1.31.abcdefghijklmnop',
  'checked_in_at': null,
  'check_in_opens_at': '2026-11-22T14:00:00+05:00',
  'check_in_closes_at': '2026-11-22T22:00:00+05:00',
};

/// A 1×1 PNG, so a poster renders without the network.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ),
);

HttpEventRepository _answering(
  List<http.Request> requests,
  int status,
  Object? body,
) => HttpEventRepository(
  ApiClient(
    baseUrl: _baseUrl,
    readToken: () async => 'jwt',
    httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response(body == null ? '' : jsonEncode(body), status);
    }),
  ),
);

void main() {
  group('v5 JSON', () {
    test('the Event object carries end, poster, check-in and rating', () {
      final event = eventFromJson(_v5Event);
      expect(
        event.endsAt.isAtSameMomentAs(
          DateTime.parse('2026-11-22T20:00:00+05:00'),
        ),
        isTrue,
      );
      expect(event.posterUrl, '/api/v1/events/7/poster?v=1763820000000');
      expect(event.isCheckedIn, isTrue);
      expect((event.myRating, event.feedbackOpen), (null, true));
      // The offline cache writes and reads the same fields.
      final again = eventFromJson(
        jsonDecode(jsonEncode(eventToJson(event))) as Map<String, Object?>,
      );
      expect(again.posterUrl, event.posterUrl);
      expect(again.checkedInAt, event.checkedInAt);
      expect(again.feedbackOpen, isTrue);
    });

    test('an older server or cache without v5 fields still parses', () {
      final old = Map<String, Object?>.of(_v5Event)
        ..removeWhere(
          (k, _) => {
            'ends_at',
            'poster_url',
            'checked_in_at',
            'my_rating',
            'feedback_open',
          }.contains(k),
        );
      final event = eventFromJson(old);
      expect(event.endsAt, event.startsAt.add(const Duration(hours: 2)));
      expect((event.posterUrl, event.checkedInAt), (null, null));
      expect(event.feedbackOpen, isFalse);
    });

    test('poster paths are resolved against the API host', () {
      const config = AppConfig(apiBaseUrl: _baseUrl, useMockApi: false);
      expect(
        absolutePosterUrl(config, '/api/v1/events/7/poster?v=1'),
        'https://qatys-api.test/api/v1/events/7/poster?v=1',
      );
      expect(absolutePosterUrl(config, null), isNull);
      const mock = AppConfig(apiBaseUrl: '', useMockApi: true);
      expect(absolutePosterUrl(mock, '/api/v1/events/7/poster'), isNull);
    });
  });

  group('HTTP', () {
    late List<http.Request> requests;
    setUp(() => requests = []);

    test('ticket: 200, waiting list, not registered, cancelled', () async {
      final ready = await _answering(requests, 200, _ticket).fetchTicket(7);
      expect(requests.single.url.path, '/api/v1/events/7/ticket');
      final ticket = (ready as TicketReady).ticket;
      expect((ticket.code, ticket.spacedCode), ('K7Q2XM', 'K7Q 2XM'));
      expect(ticket.qr, startsWith('QATYS-T1.31.'));

      Future<TicketResult> answer(int status, String code) =>
          _answering(requests, status, {'error': code}).fetchTicket(7);
      expect(
        await answer(409, 'ticket_waiting_list'),
        isA<TicketWaitingList>(),
      );
      expect(await answer(404, 'not_registered'), isA<TicketNotRegistered>());
      expect(await answer(409, 'event_cancelled'), isA<TicketEventCancelled>());
    });

    test('feedback: body, 201 and every refusal', () async {
      final sent = await _answering(
        requests,
        201,
        {},
      ).sendFeedback(7, rating: 4, comment: 'Good');
      expect(sent, isA<FeedbackSent>());
      expect(requests.single.url.path, '/api/v1/events/7/feedback');
      expect(jsonDecode(requests.single.body), {
        'rating': 4,
        'comment': 'Good',
      });

      Future<FeedbackResult> answer(int status, String code) => _answering(
        requests,
        status,
        {'error': code},
      ).sendFeedback(7, rating: 5);
      expect(await answer(403, 'not_checked_in'), isA<FeedbackNotCheckedIn>());
      expect(await answer(409, 'event_not_finished'), isA<FeedbackTooEarly>());
      expect(
        await answer(409, 'feedback_already_sent'),
        isA<FeedbackAlreadySent>(),
      );
      expect(jsonDecode(requests.last.body), {'rating': 5});
    });

    test('cancelling after check-in is a calm answer', () async {
      final result = await _answering(requests, 409, {
        'error': 'already_checked_in',
      }).cancelRegistration(7);
      expect(result, isA<CancelAlreadyCheckedIn>());
    });
  });

  group('mock server', () {
    late DateTime now;
    late MockEventRepository server;

    setUp(() {
      now = DateTime(2026, 10, 1, 12);
      server = MockEventRepository(clock: () => now, latency: Duration.zero);
    });

    test('ticket only for a confirmed place; rating only after check-in and '
        'the end, once', () async {
      expect(await server.fetchTicket(1), isA<TicketNotRegistered>());
      await server.register(1);
      expect(await server.fetchTicket(1), isA<TicketReady>());
      await server.register(5); // full: waiting list
      expect(await server.fetchTicket(5), isA<TicketWaitingList>());

      expect(
        await server.sendFeedback(1, rating: 5),
        isA<FeedbackNotCheckedIn>(),
      );
      server.checkInByOrganiser(1);
      expect(await server.cancelRegistration(1), isA<CancelAlreadyCheckedIn>());
      expect(await server.sendFeedback(1, rating: 5), isA<FeedbackTooEarly>());
      server.finishByOrganiser(1);
      expect((await server.fetchEvent(1)).feedbackOpen, isTrue);
      expect(await server.sendFeedback(1, rating: 5), isA<FeedbackSent>());
      expect(
        await server.sendFeedback(1, rating: 1),
        isA<FeedbackAlreadySent>(),
      );
      final event = await server.fetchEvent(1);
      expect((event.myRating, event.feedbackOpen), (5, false));
    });
  });

  group('screens', () {
    testWidgets('TC-16 in the app: Registered -> Ticket shows the QR and the '
        'code, then "Checked in"', (tester) async {
      useTallPhone(tester);
      final app = TestApp();
      await tester.runAsync(() => app.events.inner.register(1));
      await tester.pumpWidget(
        ProviderScope(
          overrides: app.overrides,
          child: const MaterialApp(home: EventDetailScreen(eventId: 1)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('show-ticket')));
      await tester.pumpAndSettle();

      expect(find.byType(TicketScreen), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      final code = tester.widget<SelectableText>(
        find.byKey(const ValueKey('ticket-code')),
      );
      expect(code.data, matches(RegExp(r'^[A-Z2-9]{3} [A-Z2-9]{3}$')));
      expect(find.textContaining('Show this at the door'), findsOneWidget);

      app.events.inner.checkInByOrganiser(1);
      await tester.tap(find.byTooltip('Refresh ticket'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-checked-in')), findsOneWidget);
    });

    testWidgets('the ticket opens offline from the copy saved on the phone', (
      tester,
    ) async {
      useTallPhone(tester);
      final app = TestApp();
      await tester.runAsync(() => app.events.inner.register(1));
      final event = (await tester.runAsync(
        () => app.events.inner.fetchEvent(1),
      ))!;
      Widget screen() => ProviderScope(
        overrides: app.overrides,
        child: MaterialApp(home: TicketScreen(event: event)),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(app.store.values.keys, contains('ticket.1'));

      app.events.offline = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ticket-offline')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('after check-in and the end: Rate this event -> 4 stars -> '
        'thank you, then the rating is shown', (tester) async {
      useTallPhone(tester);
      final app = TestApp();
      await tester.runAsync(() => app.events.inner.register(1));
      app.events.inner
        ..checkInByOrganiser(1)
        ..finishByOrganiser(1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: app.overrides,
          child: const MaterialApp(home: EventDetailScreen(eventId: 1)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checked-in-status')), findsOneWidget);

      final semantics = tester.ensureSemantics();
      await tester.tap(find.byKey(const ValueKey('rate-event')));
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('feedback-send'));
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('star-4')));
      await tester.pump();
      expect(find.text('Very good'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('feedback-comment')),
        'Great mentors',
      );
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(find.textContaining('Thank you! You rated it 4 of 5'), findsOne);
      expect(find.byKey(const ValueKey('rate-event')), findsNothing);
      expect(find.byKey(const ValueKey('my-rating')), findsOneWidget);
      expect(find.bySemanticsLabel('4 of 5 stars'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('TC-19 in the app: registered but never checked in -> no '
        'rating button after the end', (tester) async {
      useTallPhone(tester);
      final app = TestApp();
      await tester.runAsync(() => app.events.inner.register(1));
      app.events.inner.finishByOrganiser(1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: app.overrides,
          child: const MaterialApp(home: EventDetailScreen(eventId: 1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('not-checked-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('rate-event')), findsNothing);
      expect(find.byKey(const ValueKey('show-ticket')), findsNothing);
    });

    testWidgets('TC-18 in the app: checked in, not ended -> no rating yet', (
      tester,
    ) async {
      useTallPhone(tester);
      final app = TestApp();
      await tester.runAsync(() => app.events.inner.register(6));
      app.events.inner.checkInByOrganiser(6);
      await tester.pumpWidget(
        ProviderScope(
          overrides: app.overrides,
          child: const MaterialApp(home: EventDetailScreen(eventId: 6)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('checked-in-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('rate-event')), findsNothing);
      expect(find.text('Cancel registration'), findsNothing);
    });

    testWidgets('TC-21 in the app: a poster shows in the carousel, the feed '
        'card and the event header', (tester) async {
      useTallPhone(tester);
      final app = TestApp(
        config: const AppConfig(apiBaseUrl: _baseUrl, useMockApi: true),
      );
      app.events.inner.setPoster(6, '/api/v1/events/6/poster?v=1');
      final requested = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...app.overrides,
            posterImageProvider.overrideWithValue((url) {
              requested.add(url);
              return MemoryImage(_png);
            }),
          ],
          child: const QatysApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('announcement-poster')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-poster')), findsOneWidget);
      expect(requested.toSet(), {
        'https://qatys-api.test/api/v1/events/6/poster?v=1',
      });

      final semantics = tester.ensureSemantics();
      await tester.tap(find.byKey(const ValueKey('card-poster')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hero-poster')), findsOneWidget);
      // VoiceOver reads the poster on the event page.
      expect(
        find.bySemanticsLabel('Poster of Flutter workshop'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('My events: Show ticket for an upcoming place, Rate this '
        'event for an attended one', (tester) async {
      useTallPhone(tester);
      final app = TestApp();
      await tester.runAsync(() => app.events.inner.register(1));
      await tester.runAsync(() => app.events.inner.register(6));
      app.events.inner
        ..checkInByOrganiser(6)
        ..finishByOrganiser(6);
      await app.pump(tester);
      await openTab(tester, 'My events');

      expect(find.byKey(const ValueKey('ticket-1')), findsOneWidget);
      expect(find.text('Past (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rate-6')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('star-5')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feedback-send')));
      await tester.pumpAndSettle();

      expect(find.textContaining('You rated it 5 of 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('rated-6')), findsOneWidget);
    });
  });
}
