/// A registration tap that did not reach the server (brief §9, "Low battery /
/// app killed"). Kept on the phone and sent again later; the server's answer
/// at that moment is what counts.
enum PendingKind { register, cancel }

class PendingAction {
  const PendingAction({
    required this.eventId,
    required this.kind,
    required this.eventTitle,
    required this.queuedAt,
  });

  final int eventId;
  final PendingKind kind;

  /// For the "waiting to be sent" banner, without another request.
  final String eventTitle;
  final DateTime queuedAt;
}
