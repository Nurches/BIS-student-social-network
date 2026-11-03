import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/domain/session.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/session_controller.dart';
import 'features/event/presentation/event_detail_screen.dart';
import 'features/feed/presentation/feed_screen.dart';
import 'features/push/domain/push_service.dart';
import 'features/push/presentation/notification_permission_prompt.dart';
import 'features/push/presentation/push_controller.dart';

class QatysApp extends ConsumerStatefulWidget {
  const QatysApp({super.key});

  @override
  ConsumerState<QatysApp> createState() => _QatysAppState();
}

class _QatysAppState extends ConsumerState<QatysApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _subscriptions = <StreamSubscription<Object>>[];

  /// A notification tapped before anyone was signed in: opened after login.
  int? _pendingEventId;

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushServiceProvider);

    // TC-01: a tap on a notification opens that event's detail screen,
    // from the background and from a cold start.
    _subscriptions
      ..add(push.openedEventIds.listen(_openEvent))
      ..add(push.foregroundNotices.listen(_showNotice));
    unawaited(
      push.initialEventId().then((id) => id == null ? null : _openEvent(id)),
    );

    ref.listenManual<AsyncValue<Session?>>(sessionControllerProvider, (
      previous,
      next,
    ) {
      final wasSignedIn = previous?.value != null;
      final isSignedIn = next.value != null;
      if (isSignedIn && !wasSignedIn) _onSignedIn();
    }, fireImmediately: true);

    ref.listenManual<bool>(pushControllerProvider, (_, ask) {
      if (ask) unawaited(_askPermission());
    });
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  void _onSignedIn() {
    unawaited(ref.read(pushControllerProvider.notifier).onSignedIn());
    if (_pendingEventId case final id?) {
      _pendingEventId = null;
      // After the feed has replaced the login screen.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEvent(id));
    }
  }

  void _openEvent(int eventId) {
    final navigator = _navigator.currentState;
    if (ref.read(sessionControllerProvider).value == null ||
        navigator == null) {
      _pendingEventId = eventId;
      return;
    }
    navigator
      ..popUntil((route) => route.isFirst)
      ..push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(eventId: eventId),
        ),
      );
  }

  void _showNotice(PushNotice notice) {
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text('New event: ${notice.title}'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => _openEvent(notice.eventId),
        ),
      ),
    );
  }

  Future<void> _askPermission() async {
    final context = _navigator.currentContext;
    if (context == null) return;
    final allow = await showNotificationPermissionPrompt(context);
    await ref.read(pushControllerProvider.notifier).answerPrompt(allow: allow);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    return MaterialApp(
      title: 'Qatys',
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: switch (session) {
        AsyncData(value: _?) => const FeedScreen(),
        AsyncData() || AsyncError() => const LoginScreen(),
        AsyncLoading() => const _Splash(),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
