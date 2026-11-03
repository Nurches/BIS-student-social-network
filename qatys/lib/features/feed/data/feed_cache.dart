import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../event/data/event_json.dart';
import '../../event/domain/event.dart';

/// The last first page of the feed, so the app shows events instantly on
/// launch and while the server is unreachable (NFR-01, brief §9).
class FeedSnapshot {
  const FeedSnapshot({required this.events, required this.savedAt});

  final List<Event> events;
  final DateTime savedAt;
}

class FeedCache {
  FeedCache(this._store);

  static const _key = 'feed.v1';

  final LocalStore _store;

  /// Events whose deadline has passed since saving are dropped: the feed
  /// only lists open events.
  Future<FeedSnapshot?> read(int studentId, {required DateTime now}) async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      if (json['student_id'] != studentId) return null;
      final events = [
        for (final item in json['items']! as List<Object?>)
          eventFromJson(item! as Map<String, Object?>),
      ];
      return FeedSnapshot(
        events: [
          for (final e in events)
            if (!e.isDeadlinePassed(now)) e,
        ],
        savedAt: DateTime.parse(json['saved_at']! as String).toLocal(),
      );
    } on Object {
      await _store.remove(_key);
      return null;
    }
  }

  Future<void> write(int studentId, List<Event> events, DateTime savedAt) =>
      _store.write(
        _key,
        jsonEncode({
          'student_id': studentId,
          'saved_at': savedAt.toUtc().toIso8601String(),
          'items': [for (final e in events) eventToJson(e)],
        }),
      );
}

final feedCacheProvider = Provider<FeedCache>(
  (ref) => FeedCache(ref.watch(localStoreProvider)),
);
