// MVP extension: the four tabs, following a community, my events, the inbox,
// the profile and sign-up — on the in-memory server of mock mode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/features/community/presentation/community_screen.dart';
import 'package:qatys/features/event/presentation/event_detail_screen.dart';
import 'package:qatys/features/feed/presentation/feed_screen.dart';
import 'package:qatys/features/inbox/presentation/inbox_screen.dart';

import '../../helpers/test_app.dart';

List<String> feedTitles(WidgetTester tester) => tester
    .widgetList<EventCard>(find.byType(EventCard))
    .map((c) => c.event.title)
    .toList();

Finder followButton(String community) => find.descendant(
  of: find.ancestor(of: find.text(community), matching: find.byType(Card)),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

void main() {
  testWidgets('four tabs: Feed, Explore, My events, Profile', (tester) async {
    useTallPhone(tester);
    await TestApp().pump(tester);

    for (final label in ['Feed', 'Explore', 'My events', 'Profile']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('following a community brings its events into the feed', (
    tester,
  ) async {
    useTallPhone(tester);
    await TestApp().pump(tester);
    expect(feedTitles(tester), isNot(contains('Futsal cup')));

    await openTab(tester, 'Explore');
    expect(find.text('Following (2)'), findsOneWidget);
    expect(find.text('Sports Club'), findsOneWidget);
    await tester.tap(followButton('Sports Club'));
    await tester.pumpAndSettle();
    expect(find.text('Following (3)'), findsOneWidget);

    await openTab(tester, 'Feed');
    expect(feedTitles(tester), contains('Futsal cup'));

    await openTab(tester, 'Explore');
    await tester.tap(followButton('Sports Club'));
    await tester.pumpAndSettle();
    await openTab(tester, 'Feed');
    expect(feedTitles(tester), isNot(contains('Futsal cup')));
  });

  testWidgets('search narrows the communities', (tester) async {
    useTallPhone(tester);
    await TestApp().pump(tester);
    await openTab(tester, 'Explore');

    await tester.enterText(find.byType(TextField), 'volunt');
    await tester.pumpAndSettle();

    expect(find.text('Volunteer Hub'), findsOneWidget);
    expect(find.text('IT Club'), findsNothing);
  });

  testWidgets('a community page shows its open events, also unfollowed', (
    tester,
  ) async {
    useTallPhone(tester);
    await TestApp().pump(tester);
    await openTab(tester, 'Explore');

    await tester.tap(find.text('Volunteer Hub'));
    await tester.pumpAndSettle();

    expect(find.byType(CommunityScreen), findsOneWidget);
    expect(find.text('Campus clean-up day'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Follow'), findsOneWidget);
  });

  testWidgets('My events: empty first, then the registered event', (
    tester,
  ) async {
    useTallPhone(tester);
    await TestApp().pump(tester);
    await openTab(tester, 'My events');
    expect(find.text('No registrations yet'), findsOneWidget);

    await openTab(tester, 'Feed');
    await tester.tap(find.text('Autumn Hackathon 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openTab(tester, 'My events');
    expect(find.text('Upcoming (1)'), findsOneWidget);
    expect(find.text('Autumn Hackathon 2026'), findsOneWidget);
    expect(find.text('Registered ✓'), findsOneWidget);
  });

  testWidgets('inbox: badge, list, read, and a tap opens the event', (
    tester,
  ) async {
    useTallPhone(tester);
    await TestApp().pump(tester);
    expect(find.byTooltip('Notifications, 1 new'), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications, 1 new'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.text('New event: Flutter workshop'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget); // the dot stays

    await tester.tap(find.text('New event: CV clinic'));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsOneWidget); // read: no badge
  });

  testWidgets('profile shows the student and the numbers', (tester) async {
    useTallPhone(tester);
    await TestApp().pump(tester);

    await openTab(tester, 'Profile');

    expect(find.text('Turarbek Nurassyl'), findsOneWidget);
    expect(find.text('nurassyl@kbtu.kz'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.byTooltip('Log out'), findsOneWidget);
  });

  testWidgets('sign up creates the account and opens the feed', (tester) async {
    useTallPhone(tester);
    await TestApp(signedIn: false).pump(tester);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Aru Sadykova');
    await tester.enterText(fields.at(1), 'new.student@kbtu.kz');
    await tester.enterText(fields.at(2), 'secret-pass-1');
    await tester.enterText(fields.at(3), 'secret-pass-2');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match'), findsOneWidget);

    await tester.enterText(fields.at(3), 'secret-pass-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(FeedScreen), findsOneWidget);
    await openTab(tester, 'Profile');
    expect(find.text('Aru Sadykova'), findsOneWidget);
  });

  testWidgets('sign up with a taken email says so', (tester) async {
    useTallPhone(tester);
    await TestApp(signedIn: false).pump(tester);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Someone');
    await tester.enterText(fields.at(1), 'laila@kbtu.kz');
    await tester.enterText(fields.at(2), 'secret-pass-1');
    await tester.enterText(fields.at(3), 'secret-pass-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('An account with this email already exists. Sign in instead.'),
      findsOneWidget,
    );
  });
}
