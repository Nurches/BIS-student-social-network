import 'event.dart';
import 'feedback_result.dart';
import 'registration_result.dart';
import 'ticket.dart';

/// Access to events and registrations.
///
/// Implementations: `HttpEventRepository` (real server) and
/// `MockEventRepository` (in-memory fake, so the demo never depends on the
/// server being awake). Transport failures are thrown as `ApiException`.
abstract interface class EventRepository {
  /// Events from the communities the student follows whose registration
  /// deadline has not passed, ordered by deadline.
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor});

  /// The announcement cards on top of the home screen: open events of every
  /// confirmed community, followed or not, soonest deadline first (at most 10).
  Future<List<Event>> fetchAnnouncements();

  /// One event with fresh `freePlaces` and `myState`. Called every time the
  /// detail screen opens, because cached feed numbers go stale in seconds.
  Future<Event> fetchEvent(int id);

  Future<RegistrationResult> register(int eventId);

  /// Cancels the student's own registration or waiting-list entry.
  Future<CancelResult> cancelRegistration(int eventId);

  /// Events the student is confirmed for or waiting for, past ones included
  /// (`GET /me/registrations`).
  Future<List<Event>> fetchMyEvents();

  /// Week 13 (FR-06): the QR and the code of a confirmed place
  /// (`GET /events/{id}/ticket`).
  Future<TicketResult> fetchTicket(int eventId);

  /// Week 13 (FR-07): rate an event the student attended, once, after it
  /// ended (`POST /events/{id}/feedback`).
  Future<FeedbackResult> sendFeedback(
    int eventId, {
    required int rating,
    String? comment,
  });
}
