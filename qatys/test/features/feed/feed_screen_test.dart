import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/features/event/domain/event.dart';
import 'package:qatys/features/event/presentation/event_detail_screen.dart';
import 'package:qatys/features/feed/presentation/feed_screen.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('cards show community, title, start, deadline and free places', (
    tester,
  ) async {
    useTallPhone(tester);
    await TestApp().pump(tester);

    final card = find.ancestor(
      of: find.text('Flutter workshop'),
      matching: find.byType(EventCard),
    );
    expect(card, findsOneWidget);
    for (final text in [
      'IT Club',
      'Starts ',
      'Register by ',
      '1 of 20 places free',
    ]) {
      expect(
        find.descendant(of: card, matching: find.textContaining(text)),
        findsOneWidget,
        reason: text,
      );
    }
    expect(find.text('Full · waiting list open'), findsOneWidget); // CV clinic
  });

  testWidgets('feed is ordered by deadline and hides closed events', (
    tester,
  ) async {
    useTallPhone(tester);
    await TestApp().pump(tester);

    final titles = tester
        .widgetList<EventCard>(find.byType(EventCard))
        .map((c) => c.event.title)
        .toList();
    expect(titles, [
      'Flutter workshop',
      'CV clinic',
      'IT Career Day',
      'Autumn Hackathon 2026',
    ]);
    expect(find.text('Git workshop for first-years'), findsNothing);
  });

  testWidgets('NFR-01: a saved feed is shown at once when the server is down', (
    tester,
  ) async {
    useTallPhone(tester);
    final app = TestApp();
    await app.pump(tester); // first launch fills the cache

    // Next launch (a fresh app), no connection: same phone storage.
    await tester.pumpWidget(const SizedBox());
    final offline = TestApp(events: app.events..offline = true);
    offline.store.values.addAll(app.store.values);
    await offline.pump(tester);

    expect(find.textContaining('No connection to the server'), findsOneWidget);
    expect(find.textContaining('Saved events from'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(find.text('Flutter workshop'), findsOneWidget);
    expect(find.text('Autumn Hackathon 2026'), findsOneWidget);
  });

  testWidgets('first launch without a connection offers a retry', (
    tester,
  ) async {
    useTallPhone(tester);
    final app = TestApp(events: SwitchableEventRepository()..offline = true);
    await app.pump(tester);

    expect(find.textContaining('No connection to the server'), findsOneWidget);

    app.events.offline = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byType(EventCard), findsNWidgets(4));
  });

  testWidgets('refresh button and pull to refresh reload the feed', (
    tester,
  ) async {
    useTallPhone(tester);
    final app = TestApp();
    await app.pump(tester);
    app.events.inner.takePlaceByAnotherStudent(6); // the last place is gone

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Full · waiting list open'), findsNWidgets(2));

    await tester.fling(
      find.byType(EventCard).first,
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byType(EventCard), findsNWidgets(4));
  });

  testWidgets('empty state when there is nothing to show', (tester) async {
    useTallPhone(tester);
    await TestApp(events: _EmptyFeed()).pump(tester);

    expect(find.text('No upcoming events'), findsOneWidget);
  });

  testWidgets('tapping a card opens the event detail', (tester) async {
    useTallPhone(tester);
    await TestApp().pump(tester);

    await tester.tap(find.text('IT Career Day'));
    await tester.pumpAndSettle();

    expect(find.byType(EventDetailScreen), findsOneWidget);
    expect(find.text('Meeting with 12 companies'), findsOneWidget);
  });
}

class _EmptyFeed extends SwitchableEventRepository {
  @override
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor}) async =>
      const FeedPage(items: [], nextCursor: null);
}
