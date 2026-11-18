import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A push shown while the app is open (Android does not display those).
class PushNotice {
  const PushNotice({
    required this.title,
    required this.eventId,
    this.body = '',
    this.type = 'event_published',
    this.communityId,
  });

  final String title;
  final String body;

  /// `data.type` of docs/api.md, e.g. `event_cancelled`.
  final String type;

  /// Null only for `community_approved`, which carries [communityId].
  final int? eventId;
  final int? communityId;

  /// The snackbar line.
  String get text => switch (type) {
    'event_published' => 'New event: $title',
    _ when body.isEmpty => title,
    _ => '$title — $body',
  };
}

/// Firebase Cloud Messaging behind an interface, so the app runs without
/// Firebase (mock mode, Flutter Web, before `google-services.json` exists)
/// and tests can drive notification taps (TC-01).
abstract interface class PushService {
  /// False when the build has no Firebase: the app then never asks for the
  /// notification permission.
  bool get isAvailable;

  /// Whether the student has allowed notifications.
  Future<bool> isPermitted();

  /// Shows the system permission dialog (Android 13+); true when allowed.
  Future<bool> requestPermission();

  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// The event of the notification that launched the app from scratch.
  Future<int?> initialEventId();

  /// Events of notifications tapped while the app was in the background.
  Stream<int> get openedEventIds;

  Stream<PushNotice> get foregroundNotices;

  /// Invalidates this phone's token, so pushes for the previous account stop.
  Future<void> deleteToken();
}

class NoopPushService implements PushService {
  const NoopPushService();

  @override
  bool get isAvailable => false;

  @override
  Future<bool> isPermitted() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Future<int?> initialEventId() async => null;

  @override
  Stream<int> get openedEventIds => const Stream.empty();

  @override
  Stream<PushNotice> get foregroundNotices => const Stream.empty();

  @override
  Future<void> deleteToken() async {}
}

/// Overridden in `main()` with Firebase when it is configured.
final pushServiceProvider = Provider<PushService>(
  (ref) => const NoopPushService(),
);

/// `data: { "type": ..., "event_id": "17" }` of docs/api.md.
int? eventIdFromData(Map<String, Object?> data) =>
    int.tryParse('${data['event_id'] ?? ''}');

/// `community_approved` pushes carry `community_id` instead (Week 12).
int? communityIdFromData(Map<String, Object?> data) =>
    int.tryParse('${data['community_id'] ?? ''}');
