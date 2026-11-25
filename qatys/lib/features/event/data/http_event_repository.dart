import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/event.dart';
import '../domain/event_repository.dart';
import '../domain/feedback_result.dart';
import '../domain/registration_result.dart';
import '../domain/ticket.dart';
import 'event_json.dart';

/// [EventRepository] backed by the FastAPI server (docs/api.md).
class HttpEventRepository implements EventRepository {
  HttpEventRepository(this._api);

  final ApiClient _api;

  @override
  Future<FeedPage> fetchFeed({int limit = 20, String? cursor}) async {
    final response = await _api.get(
      '/feed',
      query: {'limit': '$limit', 'cursor': ?cursor},
    );
    _expect(response, 200);
    return _parse(() => feedPageFromJson(response.json));
  }

  @override
  Future<List<Event>> fetchAnnouncements() async {
    final response = await _api.get('/events/announcements');
    _expect(response, 200);
    return _parse(() => eventListFromJson(response.json));
  }

  @override
  Future<Event> fetchEvent(int id) async {
    final response = await _api.get('/events/$id');
    if (response.statusCode == 404) {
      throw NotFoundException('Event $id not found');
    }
    _expect(response, 200);
    return _parse(() => eventFromJson(response.json));
  }

  @override
  Future<RegistrationResult> register(int eventId) async {
    final response = await _api.post('/events/$eventId/registrations');
    return switch (response.statusCode) {
      201 => const RegistrationConfirmed(),
      200 => _parse(() => waitListedFromJson(response.json)),
      409 when _errorCode(response) == 'event_cancelled' =>
        const RegistrationEventCancelled(),
      409 => const RegistrationAlreadyExists(),
      410 => const RegistrationClosed(),
      404 => throw NotFoundException('Event $eventId not found'),
      _ => throw _unexpected(response),
    };
  }

  // docs/api.md: 200 `{ "status": "cancelled" }`. The body says nothing the
  // caller needs, so it is ignored; the caller re-fetches the event.
  @override
  Future<CancelResult> cancelRegistration(int eventId) async {
    final response = await _api.delete('/events/$eventId/registrations');
    return switch (response.statusCode) {
      200 || 204 => const CancelSucceeded(),
      404 when _errorCode(response) == 'not_registered' =>
        const CancelNotRegistered(),
      404 => throw NotFoundException('Event $eventId not found'),
      410 => const CancelEventStarted(),
      409 when _errorCode(response) == 'event_cancelled' =>
        const CancelEventCancelled(),
      409 when _errorCode(response) == 'already_checked_in' =>
        const CancelAlreadyCheckedIn(),
      _ => throw _unexpected(response),
    };
  }

  @override
  Future<List<Event>> fetchMyEvents() async {
    final response = await _api.get('/me/registrations');
    _expect(response, 200);
    return _parse(() => eventListFromJson(response.json));
  }

  @override
  Future<TicketResult> fetchTicket(int eventId) async {
    final response = await _api.get('/events/$eventId/ticket');
    return switch ((response.statusCode, _errorCode(response))) {
      (200, _) => TicketReady(_parse(() => ticketFromJson(response.json))),
      (409, 'ticket_waiting_list') => const TicketWaitingList(),
      (409, 'event_cancelled') => const TicketEventCancelled(),
      (404, 'not_registered') => const TicketNotRegistered(),
      (404, _) => throw NotFoundException('Event $eventId not found'),
      _ => throw _unexpected(response),
    };
  }

  @override
  Future<FeedbackResult> sendFeedback(
    int eventId, {
    required int rating,
    String? comment,
  }) async {
    final response = await _api.post(
      '/events/$eventId/feedback',
      body: {'rating': rating, 'comment': ?comment},
    );
    return switch ((response.statusCode, _errorCode(response))) {
      (201, _) => FeedbackSent(rating),
      (403, 'not_checked_in') => const FeedbackNotCheckedIn(),
      (409, 'event_not_finished') => const FeedbackTooEarly(),
      (409, 'feedback_already_sent') => const FeedbackAlreadySent(),
      (409, 'event_cancelled') => const FeedbackEventCancelled(),
      (404, _) => throw NotFoundException('Event $eventId not found'),
      _ => throw _unexpected(response),
    };
  }

  String? _errorCode(ApiResponse response) {
    final body = response.body;
    return body is Map<String, Object?> ? body['error'] as String? : null;
  }

  void _expect(ApiResponse response, int status) {
    if (response.statusCode != status) throw _unexpected(response);
  }

  UnexpectedResponseException _unexpected(ApiResponse response) =>
      UnexpectedResponseException(
        'Unexpected status ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException catch (e) {
      throw UnexpectedResponseException('Malformed response: ${e.message}');
    }
  }
}
