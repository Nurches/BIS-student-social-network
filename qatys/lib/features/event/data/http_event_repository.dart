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

  // TODO(confirm): GET /events/{id} is required by the brief (fresh free
  // places on the detail screen) but is not yet listed in docs/api.md.
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

  // TODO(confirm): the response body of DELETE is not defined in
  // docs/api.md, so it is ignored; the caller re-fetches the event.
  @override
  Future<void> cancelRegistration(int eventId) async {
    final response = await _api.delete('/events/$eventId/registrations');
    if (response.statusCode == 404) {
      throw NotFoundException('No registration for event $eventId');
    }
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw _unexpected(response);
    }
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
