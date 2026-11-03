import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/push/data/firebase_push_service.dart';
import 'features/push/domain/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Null without google-services.json: the app works, just without pushes.
  final push = await FirebasePushService.tryCreate();
  runApp(
    ProviderScope(
      overrides: [
        if (push != null) pushServiceProvider.overrideWithValue(push),
      ],
      child: const QatysApp(),
    ),
  );
}
