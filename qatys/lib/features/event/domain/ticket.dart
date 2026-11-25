/// Week 13 (FR-06): the ticket of a confirmed place. The organiser scans
/// [qr] at the door, or types [code] when the QR cannot be shown.
class Ticket {
  const Ticket({
    required this.eventId,
    required this.registrationId,
    required this.code,
    required this.qr,
    required this.checkedInAt,
    required this.checkInOpensAt,
    required this.checkInClosesAt,
  });

  final int eventId;
  final int registrationId;

  /// 6 characters without look-alikes (no 0/O, 1/I/L).
  final String code;

  /// The text inside the QR code, signed by the server.
  final String qr;
  final DateTime? checkedInAt;
  final DateTime checkInOpensAt;
  final DateTime checkInClosesAt;

  /// The code split for reading aloud: `K7Q 2XM`.
  String get spacedCode =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}

/// Expected outcomes of `GET /events/{id}/ticket`.
sealed class TicketResult {
  const TicketResult();
}

final class TicketReady extends TicketResult {
  const TicketReady(this.ticket, {this.offlineCopy = false});

  final Ticket ticket;

  /// No connection: the copy saved the last time it was opened.
  final bool offlineCopy;
}

/// 409 `ticket_waiting_list`: no place yet, so no ticket.
final class TicketWaitingList extends TicketResult {
  const TicketWaitingList();
}

/// 404 `not_registered`.
final class TicketNotRegistered extends TicketResult {
  const TicketNotRegistered();
}

/// 409 `event_cancelled`.
final class TicketEventCancelled extends TicketResult {
  const TicketEventCancelled();
}
