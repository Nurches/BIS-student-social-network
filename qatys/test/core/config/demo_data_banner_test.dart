// W11-2: a release build without API_BASE_URL must not pass for the real
// system (an archive made from Xcode's menu silently uses mock data).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/app.dart';
import 'package:qatys/core/config/app_config.dart';
import 'package:qatys/core/config/demo_data_banner.dart';
import 'package:qatys/core/storage/local_store.dart';
import 'package:qatys/features/auth/data/auth_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_app.dart';

Future<void> pumpLogin(WidgetTester tester, AppConfig config) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
        localStoreProvider.overrideWithValue(InMemoryStore()),
      ],
      child: const QatysApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('only a release on mock data without ALLOW_MOCK_RELEASE warns', () {
    const cases = {
      AppConfig(apiBaseUrl: '', useMockApi: true, isRelease: true): true,
      AppConfig(
        apiBaseUrl: '',
        useMockApi: true,
        isRelease: true,
        allowMockRelease: true,
      ): false,
      AppConfig(apiBaseUrl: '', useMockApi: true): false, // debug run
      AppConfig(
        apiBaseUrl: 'https://qatys-api.onrender.com/api/v1',
        useMockApi: false,
        isRelease: true,
      ): false,
    };
    cases.forEach((config, warns) {
      expect(config.showsDemoDataWarning, warns);
    });
  });

  testWidgets('release on mock data shows the red banner on the login screen', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      const AppConfig(apiBaseUrl: '', useMockApi: true, isRelease: true),
    );

    expect(find.text(DemoDataBanner.text), findsOneWidget);
    expect(find.text('Sign in with your university account'), findsOneWidget);
  });

  testWidgets('the banner stays on the feed and on pushed screens', (
    tester,
  ) async {
    await TestApp(
      config: const AppConfig(
        apiBaseUrl: '',
        useMockApi: true,
        isRelease: true,
      ),
    ).pump(tester);
    expect(find.text(DemoDataBanner.text), findsOneWidget);

    await tester.tap(find.byType(Card).first);
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text(DemoDataBanner.text), findsOneWidget);
  });

  testWidgets('no banner when API_BASE_URL is set', (tester) async {
    await pumpLogin(
      tester,
      const AppConfig(
        apiBaseUrl: 'https://qatys-api.onrender.com/api/v1',
        useMockApi: false,
        isRelease: true,
      ),
    );

    expect(find.text(DemoDataBanner.text), findsNothing);
  });
}
