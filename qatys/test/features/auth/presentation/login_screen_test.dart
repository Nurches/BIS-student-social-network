import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/app.dart';
import 'package:qatys/core/config/app_config.dart';
import 'package:qatys/features/auth/data/auth_providers.dart';
import 'package:qatys/features/auth/data/mock_auth_repository.dart';

import '../../../helpers/fakes.dart';

void main() {
  late InMemorySessionStorage storage;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(apiBaseUrl: '', useMockApi: true),
          ),
          sessionStorageProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(
            MockAuthRepository(latency: Duration.zero),
          ),
        ],
        child: const QatysApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(
    WidgetTester tester,
    String email,
    String password,
  ) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  setUp(() => storage = InMemorySessionStorage());

  testWidgets('non-university email is rejected inline (BR-01)', (
    tester,
  ) async {
    await pumpApp(tester);

    await signIn(tester, 'student@gmail.com', 'whatever');

    expect(
      find.text('Use your university email (name@kbtu.kz)'),
      findsOneWidget,
    );
    expect(storage.session, isNull);
  });

  testWidgets('signs in, then logout clears the stored token', (tester) async {
    await pumpApp(tester);

    await signIn(tester, 'nurassyl@kbtu.kz', MockAuthRepository.demoPassword);

    expect(
      find.textContaining('Signed in as Turarbek Nurassyl'),
      findsOneWidget,
    );
    expect(storage.session, isNotNull);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(storage.session, isNull);
  });

  testWidgets('wrong password shows an inline error', (tester) async {
    await pumpApp(tester);

    await signIn(tester, 'nurassyl@kbtu.kz', 'nope');

    expect(find.text('Wrong email or password.'), findsOneWidget);
  });

  testWidgets('lockout shows the minutes left (NFR-02)', (tester) async {
    await pumpApp(tester);

    for (var i = 0; i < MockAuthRepository.maxFailedAttempts; i++) {
      await signIn(tester, 'nurassyl@kbtu.kz', 'nope');
    }

    expect(
      find.text(
        'Too many failed attempts. The account is locked. '
        'Try again in 15 minutes.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sign-in controls are at least 48 dp tall', (tester) async {
    await pumpApp(tester);

    final button = tester.getSize(find.widgetWithText(FilledButton, 'Sign in'));
    final toggle = tester.getSize(find.byTooltip('Show password'));

    expect(button.height, greaterThanOrEqualTo(48));
    expect(toggle.height, greaterThanOrEqualTo(48));
  });
}
