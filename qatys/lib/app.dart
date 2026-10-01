import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/session.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/session_controller.dart';

class QatysApp extends ConsumerWidget {
  const QatysApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    return MaterialApp(
      title: 'Qatys',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: switch (session) {
        AsyncData(value: final session?) => _SignedInHome(session: session),
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

// Temporary home screen until the feed exists (step 4).
class _SignedInHome extends ConsumerWidget {
  const _SignedInHome({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final source = config.useMockApi ? 'mock data' : config.apiBaseUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Qatys'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Signed in as ${session.student.fullName}\nData source: $source',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
