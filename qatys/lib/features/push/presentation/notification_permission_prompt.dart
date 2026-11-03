import 'package:flutter/material.dart';

/// Brief §7: asked after the first login, with one sentence saying why —
/// never on a cold start before the student knows what the app is.
Future<bool> showNotificationPermissionPrompt(BuildContext context) async {
  final allow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: const Text('Turn on notifications?'),
      content: const Text(
        'We notify you the moment a community you follow publishes an '
        'event, so you can register before the places run out.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  return allow ?? false;
}
