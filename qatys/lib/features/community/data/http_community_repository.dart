import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/json_fields.dart';
import '../../event/data/event_json.dart';
import '../../event/domain/event.dart';
import '../domain/community.dart';
import '../domain/community_repository.dart';
import 'community_json.dart';

/// [CommunityRepository] backed by the FastAPI server (docs/api.md).
class HttpCommunityRepository implements CommunityRepository {
  HttpCommunityRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Community>> fetchCommunities() async {
    final response = await _api.get('/communities');
    _expect(response, 200);
    return _parse(
      () => [
        for (final item in jsonObjects(response.body, 'Communities'))
          communityFromJson(item),
      ],
    );
  }

  @override
  Future<void> setSubscribed(
    int communityId, {
    required bool subscribed,
  }) async {
    final path = '/communities/$communityId/subscription';
    final response = subscribed
        ? await _api.put(path)
        : await _api.delete(path);
    if (response.statusCode == 404) {
      throw NotFoundException('Community $communityId not found');
    }
    _expect(response, 204);
  }

  @override
  Future<List<Event>> fetchCommunityEvents(int communityId) async {
    final response = await _api.get('/communities/$communityId/events');
    if (response.statusCode == 404) {
      throw NotFoundException('Community $communityId not found');
    }
    _expect(response, 200);
    return _parse(() => eventListFromJson(response.json));
  }

  void _expect(ApiResponse response, int status) {
    if (response.statusCode != status) {
      throw UnexpectedResponseException(
        'Unexpected status ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException catch (e) {
      throw UnexpectedResponseException('Malformed response: ${e.message}');
    }
  }
}
