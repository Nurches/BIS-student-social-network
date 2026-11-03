import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:qatys/app.dart';
import 'package:qatys/core/config/app_config.dart';
import 'package:qatys/core/network/api_exception.dart';
import 'package:qatys/core/storage/local_store.dart';
import 'package:qatys/features/auth/data/auth_providers.dart';
import 'package:qatys/features/auth/data/mock_auth_repository.dart';
import 'package:qatys/features/event/data/event_repository_provider.dart';
import 'package:qatys/features/event/data/mock_event_repository.dart';
import 'package:qatys/features/event/domain/event.dart';
import 'package:qatys/features/event/domain/event_repository.dart';
import 'package:qatys/features/event/domain/registration_result.dart';
import 'package:qatys/features/push/data/device_token_repository.dart';
import 'package:qatys/features/push/domain/push_service.dart';

import 'fakes.dart';

/// The in-memory event server of mock mode, with a switch that makes every
/// call fail like a phone without a connection.
class SwitchableEventRepository implements EventRepository {
  SwitchableEventRepository([MockEventRepository? inner])
    : inner = inner ?? MockEventRepository(latency: Duration.zero);

  final MockEventRepository inner;
  bool offline = false;
  int registerCalls = 0;

  Future<T> _call<T>(Future<T> Function() call) {
    if (offline) throw const NetworkException('offline');
    return call();
  }

  @override
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor}) =>
      _call(() => inner.fetchFeed(limit: limit, cursor: cursor));

  @override
  Future<Event> fetchEvent(int id) => _call(() => inner.fetchEvent(id));

  @override
  Future<RegistrationResult> register(int eventId) => _call(() {
    registerCalls++;
    return inner.register(eventId);
  });

  @override
  Future<CancelResult> cancelRegistration(int eventId) =>
      _call(() => inner.cancelRegistration(eventId));
}

class FakePushService implements PushService {
  final opened = StreamController<int>.broadcast();
  final notices = StreamController<PushNotice>.broadcast();
  int? initial;
  bool permitted = false;
  bool grantOnRequest = true;
  int permissionRequests = 0;
  String? currentToken = 'fcm-token-1';
  bool tokenDeleted = false;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> isPermitted() async => permitted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    permitted = grantOnRequest;
    return permitted;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Future<int?> initialEventId() async => initial;

  @override
  Stream<int> get openedEventIds => opened.stream;

  @override
  Stream<PushNotice> get foregroundNotices => notices.stream;

  @override
  Future<void> deleteToken() async => tokenDeleted = true;
}

class RecordingDeviceTokens implements DeviceTokenRepository {
  final saved = <String>[];
  final deleted = <String>[];

  @override
  Future<void> save(String token) async => saved.add(token);

  @override
  Future<void> delete(String token) async => deleted.add(token);
}

class TestApp {
  TestApp({
    this.signedIn = true,
    SwitchableEventRepository? events,
    PushService? push,
  }) : events = events ?? SwitchableEventRepository(),
       push = push ?? const NoopPushService();

  final bool signedIn;
  final SwitchableEventRepository events;
  final PushService push;
  final store = InMemoryStore();
  final tokens = RecordingDeviceTokens();
  late final InMemorySessionStorage sessions = InMemorySessionStorage(
    signedIn
        ? sessionExpiringAt(DateTime.now().add(const Duration(hours: 12)))
        : null,
  );

  List<Override> get overrides => [
    appConfigProvider.overrideWithValue(
      const AppConfig(apiBaseUrl: '', useMockApi: true),
    ),
    sessionStorageProvider.overrideWithValue(sessions),
    authRepositoryProvider.overrideWithValue(
      MockAuthRepository(latency: Duration.zero),
    ),
    eventRepositoryProvider.overrideWithValue(events),
    localStoreProvider.overrideWithValue(store),
    pushServiceProvider.overrideWithValue(push),
    deviceTokenRepositoryProvider.overrideWithValue(tokens),
  ];

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const QatysApp()),
    );
    await tester.pumpAndSettle();
  }
}

/// A 5-inch phone: 320 × 568 dp (brief §8).
void useSmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(320, 568) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}
