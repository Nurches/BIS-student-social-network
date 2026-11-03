import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/app.dart';
import 'package:qatys/core/config/app_config.dart';
import 'package:qatys/core/storage/local_store.dart';
import 'package:qatys/features/auth/data/auth_providers.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('app starts on the login screen when nobody is signed in', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(apiBaseUrl: '', useMockApi: true),
          ),
          sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
          localStoreProvider.overrideWithValue(InMemoryStore()),
        ],
        child: const QatysApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in with your university account'), findsOneWidget);
    expect(find.textContaining('Demo mode'), findsOneWidget);
  });
}
