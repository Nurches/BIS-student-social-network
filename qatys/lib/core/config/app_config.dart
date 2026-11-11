import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration passed with `--dart-define`.
///
/// `API_BASE_URL` is the full prefix including the version segment,
/// e.g. `https://qatys-api.onrender.com/api/v1` (see docs/api.md).
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.useMockApi,
    this.isRelease = false,
    this.allowMockRelease = false,
  });

  const AppConfig.fromEnvironment()
    : apiBaseUrl = _apiBaseUrl,
      useMockApi = _useMockApi,
      isRelease = kReleaseMode,
      allowMockRelease = _allowMockRelease;

  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Mock repositories are used whenever no server URL is given, so the demo
  // never depends on the server being awake.
  static const bool _useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: _apiBaseUrl == '',
  );

  // A release build on mock data on purpose (last-resort demo fallback).
  static const bool _allowMockRelease = bool.fromEnvironment(
    'ALLOW_MOCK_RELEASE',
  );

  final String apiBaseUrl;
  final bool useMockApi;

  /// `flutter build ipa/apk --release` (TestFlight, store builds).
  final bool isRelease;

  /// `--dart-define=ALLOW_MOCK_RELEASE=true`: mock data in release is intended.
  final bool allowMockRelease;

  /// W11-2: a release archived without `--dart-define=API_BASE_URL=...` (for
  /// example from Xcode's menu) silently runs on mock data. Such a build shows
  /// a red banner on every screen instead of passing for the real system.
  bool get showsDemoDataWarning => isRelease && useMockApi && !allowMockRelease;
}

/// Overridden in tests to run the app against a specific configuration.
final appConfigProvider = Provider<AppConfig>(
  (ref) => const AppConfig.fromEnvironment(),
);
