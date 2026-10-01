import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/app.dart';
import 'package:qatys/core/config/app_config.dart';

void main() {
  testWidgets('app starts on mock data when no API URL is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(apiBaseUrl: '', useMockApi: true),
          ),
        ],
        child: const QatysApp(),
      ),
    );

    expect(find.text('Qatys'), findsOneWidget);
    expect(find.text('Data source: mock data'), findsOneWidget);
  });
}
