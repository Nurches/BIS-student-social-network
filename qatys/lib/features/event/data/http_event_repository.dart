import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/event.dart';
import '../domain/event_repository.dart';
import '../domain/registration_result.dart';
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
      _ => throw _unexpected(response),
    };
  }

  @override
  Future<List<Event>> fetchMyEvents() async {
    final response = await _api.get('/me/registrations');
    _expect(response, 200);
    return _parse(() => eventListFromJson(response.json));
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
