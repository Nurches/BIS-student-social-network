import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration passed with `--dart-define`.
///
/// `API_BASE_URL` is the full prefix including the version segment,
/// e.g. `https://qatys-api.onrender.com/api/v1` (see docs/api.md).
class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.useMockApi});

  const AppConfig.fromEnvironment()
    : apiBaseUrl = _apiBaseUrl,
      useMockApi = _useMockApi;

  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Mock repositories are used whenever no server URL is given, so the demo
  // never depends on the server being awake.
  static const bool _useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: _apiBaseUrl == '',
  );

  final String apiBaseUrl;
  final bool useMockApi;
}

/// Overridden in tests to run the app against a specific configuration.
final appConfigProvider = Provider<AppConfig>(
  (ref) => const AppConfig.fromEnvironment(),
);
