import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/features/event/presentation/event_detail_screen.dart';

import '../../../helpers/test_app.dart';

/// Mock events (MockEventRepository): 1 Hackathon (27 free), 3 Git workshop
/// (deadline passed), 5 CV clinic (full), 6 Flutter workshop (1 place left).
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

void main() {
  testWidgets('TC-02: Register while places are free → Registered ✓', (
    tester,
  ) async {
    await openEvent(tester, 1);

    await tester.tap(button('Register'));
    await tester.pumpAndSettle();

    expect(find.text('Registered ✓'), findsOneWidget);
    expect(find.text("You're registered."), findsOneWidget);
    expect(find.textContaining('26 of 30'), findsOneWidget);
    expect(button('Cancel registration'), findsOneWidget);
  });

  testWidgets('TC-03: a full event offers the waiting list, calmly', (
    tester,
  ) async {
    await openEvent(tester, 5);
    expect(find.textContaining('None — waiting list open'), findsOneWidget);

    await tester.tap(button('Join waiting list'));
    await tester.pumpAndSettle();

    expect(find.text('You are number 3 on the waiting list.'), findsOneWidget);
    expect(find.textContaining('The event is full.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing, reason: 'not an error');
    expect(button('Leave waiting list'), findsOneWidget);
  });

  testWidgets('a passed deadline renders a disabled "Registration closed"', (
    tester,
  ) async {
    await openEvent(tester, 3);

    final closed = tester.widget<FilledButton>(button('Registration closed'));
    expect(closed.onPressed, isNull);
    expect(find.textContaining('(closed)'), findsOneWidget);
  });

  testWidgets('race on the last place: the loser lands on the waiting list', (
    tester,
  ) async {
    final app = await openEvent(tester, 6);
    expect(button('Register'), findsOneWidget); // the screen still says 1 left
    app.events.inner.takePlaceByAnotherStudent(6); // someone else was faster

    await tester.tap(button('Register'));
    await tester.pumpAndSettle();

    expect(find.text('You are number 1 on the waiting list.'), findsOneWidget);
    expect(find.textContaining('None — waiting list open'), findsOneWidget);
  });

  testWidgets('cancel asks first, then frees the place', (tester) async {
    await openEvent(tester, 1);
    await tester.tap(button('Register'));
    await tester.pumpAndSettle();

    await tester.tap(button('Cancel registration'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel your registration?'), findsOneWidget);
    await tester.tap(find.text('Keep my place'));
    await tester.pumpAndSettle();
    expect(find.text('Registered ✓'), findsOneWidget);

    await tester.tap(button('Cancel registration'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel registration'));
    await tester.pumpAndSettle();

    expect(find.text('Registration cancelled.'), findsOneWidget);
    expect(button('Register'), findsOneWidget);
    expect(find.textContaining('27 of 30'), findsOneWidget);
  });

  testWidgets('the screen re-fetches the event when it opens (stale list)', (
    tester,
  ) async {
    final app = TestApp();
    await app.pump(tester);
    expect(find.text('1 of 20 places free'), findsOneWidget);
    app.events.inner.takePlaceByAnotherStudent(6);

    await tester.tap(find.text('Flutter workshop'));
    await tester.pumpAndSettle();

    expect(find.textContaining('None — waiting list open'), findsOneWidget);
    expect(button('Join waiting list'), findsOneWidget);
  });

  for (final (eventId, label) in [
    (1, 'Register'),
    (5, 'Join waiting list'),
    (3, 'Registration closed'),
  ]) {
    testWidgets('320 dp phone: deadline, free places and "$label" fit '
        'without scrolling, button in the bottom third', (tester) async {
      useSmallPhone(tester);
      await openEvent(tester, eventId);

      const screen = Size(320, 568);
      for (final finder in [
        find.byKey(const ValueKey('deadline')),
        find.byKey(const ValueKey('free-places')),
        button(label),
      ]) {
        final rect = tester.getRect(finder);
        expect(
          rect.bottom,
          lessThanOrEqualTo(screen.height),
          reason: '$finder',
        );
        expect(rect.right, lessThanOrEqualTo(screen.width), reason: '$finder');
      }
      final action = tester.getRect(button(label));
      expect(action.top, greaterThanOrEqualTo(screen.height * 2 / 3));
      expect(action.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });
  }

  group('offline (brief §9, "Low battery / app killed")', () {
    testWidgets('a tap without a connection is saved and sent later', (
      tester,
    ) async {
      final app = await openEvent(tester, 1);
      app.events.offline = true;

      await tester.tap(button('Register'));
      await tester.pumpAndSettle();

      expect(
        find.text('Registration saved offline — not sent yet.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No connection to the server'),
        findsOneWidget,
      );
      expect(app.events.registerCalls, 0);

      app.events.offline = false;
      await tester.tap(button('Send now'));
      await tester.pumpAndSettle();

      expect(app.events.registerCalls, 1);
      expect(find.text('Registered ✓'), findsOneWidget);
    });

    testWidgets('the queue survives an app restart and is sent on launch', (
      tester,
    ) async {
      final app = await openEvent(tester, 1);
      app.events.offline = true;
      await tester.tap(button('Register'));
      await tester.pumpAndSettle();

      // The app is killed; next launch the server is reachable again.
      await tester.pumpWidget(const SizedBox());
      app.events.offline = false;
      final next = TestApp(events: app.events);
      next.store.values.addAll(app.store.values);
      await next.pump(tester);

      expect(app.events.registerCalls, 1);
      expect(find.text('Registered ✓'), findsOneWidget); // on the feed card
    });

    testWidgets('undo drops the saved tap', (tester) async {
      final app = await openEvent(tester, 1);
      app.events.offline = true;
      await tester.tap(button('Register'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await tester.pumpAndSettle();

      expect(button('Register'), findsOneWidget);
      app.events.offline = false;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(app.events.registerCalls, 0);
    });
  });
}
