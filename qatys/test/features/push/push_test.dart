import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/features/auth/data/mock_auth_repository.dart';
import 'package:qatys/features/event/presentation/event_detail_screen.dart';
import 'package:qatys/features/push/domain/push_service.dart';
import 'package:qatys/features/push/presentation/push_controller.dart';

import '../../helpers/test_app.dart';

void main() {
  late FakePushService push;

  setUp(() => push = FakePushService()..permitted = true);

  /// Marks the permission as already asked, so no prompt gets in the way.
  TestApp appWith({bool signedIn = true}) {
    final app = TestApp(signedIn: signedIn, push: push);
    app.store.values[PushController.askedKey] = 'yes';
    return app;
  }

  group('TC-01: tapping a notification opens the right event', () {
    testWidgets('app in the background', (tester) async {
      await appWith().pump(tester);

      push.opened.add(5);
      await tester.pumpAndSettle();

      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.text('CV clinic'), findsOneWidget);
    });

    testWidgets('app launched by the notification (cold start)', (
      tester,
    ) async {
      push.initial = 2;
      await appWith().pump(tester);

      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.text('IT Career Day'), findsOneWidget);
    });

    testWidgets('a second tap replaces the open event', (tester) async {
      await appWith().pump(tester);
      push.opened.add(5);
      await tester.pumpAndSettle();

      push.opened.add(1);
      await tester.pumpAndSettle();

      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.text('Autumn Hackathon 2026'), findsOneWidget);
    });

    testWidgets('signed out: the event opens right after login', (
      tester,
    ) async {
      await appWith(signedIn: false).pump(tester);
      push.opened.add(6);
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsNothing);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'nurassyl@kbtu.kz',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        MockAuthRepository.demoPassword,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.text('Flutter workshop'), findsOneWidget);
    });
  });

  testWidgets('a push while the app is open shows a banner with "Open"', (
    tester,
  ) async {
    await appWith().pump(tester);

    push.notices.add(const PushNotice(title: 'Career Day', eventId: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // snackbar slides in
    expect(find.text('New event: Career Day'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('IT Career Day'), findsOneWidget);
  });

  group('permission prompt (brief §7)', () {
    testWidgets('asked once after the first login, then the token is sent', (
      tester,
    ) async {
      push.permitted = false;
      final app = TestApp(push: push);
      await app.pump(tester);

      expect(find.text('Turn on notifications?'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(push.permissionRequests, 1);
      expect(app.tokens.saved, ['fcm-token-1']);
      expect(app.store.values[PushController.askedKey], 'yes');
    });

    testWidgets('"Not now" is respected and not asked again', (tester) async {
      push.permitted = false;
      final app = TestApp(push: push);
      await app.pump(tester);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(push.permissionRequests, 0);
      expect(app.tokens.saved, isEmpty);

      await tester.pumpWidget(const SizedBox());
      final next = TestApp(push: push);
      next.store.values.addAll(app.store.values);
      await next.pump(tester);
      expect(find.text('Turn on notifications?'), findsNothing);
    });

    testWidgets('never asked without Firebase (mock mode, Web)', (
      tester,
    ) async {
      await TestApp().pump(tester);
      expect(find.text('Turn on notifications?'), findsNothing);
    });

    testWidgets('already allowed: the token is sent on every launch', (
      tester,
    ) async {
      final app = appWith();
      await app.pump(tester);
      expect(app.tokens.saved, ['fcm-token-1']);
    });
  });

  testWidgets('logout: token removed on the server and on the phone, '
      'local data cleared (shared device, brief §9)', (tester) async {
    final app = appWith();
    await app.pump(tester);
    expect(app.store.values, isNotEmpty); // feed cache

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(app.tokens.deleted, ['fcm-token-1']);
    expect(push.tokenDeleted, isTrue);
    expect(app.store.values, isEmpty);
    expect(app.sessions.session, isNull);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
}
