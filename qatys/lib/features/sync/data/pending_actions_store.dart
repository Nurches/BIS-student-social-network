import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../domain/pending_action.dart';

/// The offline queue, stored per student so another account on the same
/// phone never sends someone else's taps.
class PendingActionsStore {
  PendingActionsStore(this._store);

  static const _key = 'pending_actions.v1';

  final LocalStore _store;

  Future<List<PendingAction>> read(int studentId) async {
    final raw = await _store.read(_key);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      if (json['student_id'] != studentId) return const [];
      return [
        for (final item in json['actions']! as List<Object?>)
          _fromJson(item! as Map<String, Object?>),
      ];
    } on Object {
      // A corrupt entry must not block the app: drop the queue.
      await _store.remove(_key);
      return const [];
    }
  }

  Future<void> write(int studentId, List<PendingAction> actions) {
    if (actions.isEmpty) return _store.remove(_key);
    return _store.write(
      _key,
      jsonEncode({
        'student_id': studentId,
        'actions': [for (final a in actions) _toJson(a)],
      }),
    );
  }

  static Map<String, Object?> _toJson(PendingAction a) => {
    'event_id': a.eventId,
    'kind': a.kind.name,
    'event_title': a.eventTitle,
    'queued_at': a.queuedAt.toUtc().toIso8601String(),
  };

  static PendingAction _fromJson(Map<String, Object?> json) => PendingAction(
    eventId: json['event_id']! as int,
    kind: PendingKind.values.byName(json['kind']! as String),
    eventTitle: json['event_title']! as String,
    queuedAt: DateTime.parse(json['queued_at']! as String),
  );
}

final pendingActionsStoreProvider = Provider<PendingActionsStore>(
  (ref) => PendingActionsStore(ref.watch(localStoreProvider)),
);
