import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';

class QatysApp extends StatelessWidget {
  const QatysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qatys',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: const _SkeletonHome(),
    );
  }
}

// Temporary home screen until the login and feed features exist (steps 3–4).
class _SkeletonHome extends ConsumerWidget {
  const _SkeletonHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final source = config.useMockApi ? 'mock data' : config.apiBaseUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('Qatys')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Data source: $source',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
