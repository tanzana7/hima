import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models/models.dart';

class HttpApiClient implements ApiClient {
  HttpApiClient({required String baseUrl, http.Client? client})
    : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Map<String, Guild> _guildsById = {};
  String? _token;

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = encodeJson(body);
    }
    final token = _token;
    if (authenticated && token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var code = 'request_failed';
      var message = 'リクエストに失敗しました。';
      final responseBody = response.body;
      if (responseBody.isNotEmpty) {
        try {
          final root = readJsonMap(decodeJson(responseBody));
          final error = readJsonMap(root['error']);
          code = readOptionalString(error, 'code') ?? code;
          message = readOptionalString(error, 'message') ?? message;
        } on FormatException {
          // Keep a localized fallback when a proxy returns a non-API body.
        }
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    return decodeJson(response.body);
  }

  JsonMap _map(Object? value) => readJsonMap(value);

  List<T> _list<T>(Object? value, T Function(JsonMap) fromJson) =>
      readModelList(value, fromJson);

  List<T> _array<T>(Object? value, String key, T Function(JsonMap) fromJson) =>
      _list(_map(value)[key], fromJson);

  @override
  Future<UserProfile> loginWithDiscord(DiscordAuthRequest? request) async {
    if (request == null) {
      throw StateError('Discord OAuth request is required.');
    }
    final response = _map(
      await _request(
        'POST',
        '/auth/discord',
        body: request.toJson(),
        authenticated: false,
      ),
    );
    _token = readString(response, 'access_token');
    return UserProfile.fromJson(response);
  }

  @override
  Future<void> logout() async {
    _token = null;
  }

  @override
  Future<UserProfile> getMe() async =>
      UserProfile.fromJson(_map(await _request('GET', '/me')));

  @override
  Future<UserSettings> updateSettings(UserSettings settings) async =>
      UserSettings.fromJson(
        _map(
          _map(
            await _request('PATCH', '/me/settings', body: settings.toJson()),
          )['settings'],
        ),
      );

  @override
  Future<List<Guild>> getGuilds() async {
    final guilds = _array(
      await _request('GET', '/guilds'),
      'guilds',
      Guild.fromJson,
    );
    _guildsById
      ..clear()
      ..addEntries(guilds.map((guild) => MapEntry(guild.id, guild)));
    return guilds;
  }

  @override
  Future<Guild> updateGuildVisibility(String guildId, bool visible) async {
    final response = _map(
      await _request(
        'PATCH',
        '/guilds/${Uri.encodeComponent(guildId)}',
        body: {'visible': visible},
      ),
    );
    final id = readString(response, 'id');
    final responseName = readOptionalString(response, 'name');
    var name = responseName ?? _guildsById[id]?.name;
    if (name == null) {
      for (final guild in await getGuilds()) {
        if (guild.id == id) {
          name = guild.name;
          break;
        }
      }
    }
    if (name == null) {
      throw const FormatException(
        'PATCH /guilds response has no name and the guild is not in GET /guilds.',
      );
    }
    final updated = Guild(
      id: id,
      name: name,
      visible: readBool(response, 'visible'),
    );
    _guildsById[id] = updated;
    return updated;
  }

  @override
  Future<HimaSession?> getMyHima() async {
    final response = await _request('GET', '/hima/me');
    final hima = _map(response)['hima'];
    return hima == null ? null : HimaSession.fromJson(_map(hima));
  }

  @override
  Future<HimaSession> putMyHima(HimaDeclaration declaration) async =>
      HimaSession.fromJson(
        _map(
          _map(
            await _request('PUT', '/hima/me', body: declaration.toJson()),
          )['hima'],
        ),
      );

  @override
  Future<void> deleteMyHima() async {
    await _request('DELETE', '/hima/me');
  }

  @override
  Future<List<HimaSession>> getHima() async =>
      _array(await _request('GET', '/hima'), 'hima', HimaSession.fromJson);

  @override
  Future<List<FriendServer>> getFriends() async => _array(
    await _request('GET', '/friends'),
    'servers',
    FriendServer.fromJson,
  );

  @override
  Future<List<MatchRecord>> getMatches({DateTime? since}) async {
    final sinceValue = since?.toUtc().toIso8601String();
    final query = sinceValue == null
        ? ''
        : '?since=${Uri.encodeQueryComponent(sinceValue)}';
    return _array(
      await _request('GET', '/matches$query'),
      'matches',
      MatchRecord.fromJson,
    );
  }

  @override
  Future<Knock> createKnock({
    required String userId,
    required KnockTemplate template,
  }) async => Knock.fromJson(
    _map(
      _map(
        await _request(
          'POST',
          '/knocks',
          body: {'to_user_id': userId, 'template': template.name},
        ),
      )['knock'],
    ),
  );

  @override
  Future<List<Knock>> getKnockInbox() async =>
      _array(await _request('GET', '/knocks/inbox'), 'knocks', Knock.fromJson);

  @override
  Future<List<Knock>> getKnockSent() async =>
      _array(await _request('GET', '/knocks/sent'), 'knocks', Knock.fromJson);

  @override
  Future<void> respondToKnock(String knockId, KnockStatus response) async {
    await _request(
      'POST',
      '/knocks/${Uri.encodeComponent(knockId)}/respond',
      body: {'response': response.name},
    );
  }

  @override
  Future<DateTime?> markKnockResultSeen(String knockId) async {
    final response = _map(
      await _request('POST', '/knocks/${Uri.encodeComponent(knockId)}/seen'),
    );
    return readOptionalDateTime(response, 'result_seen_at');
  }

  @override
  Future<List<BlockedUser>> getBlocks() async =>
      _array(await _request('GET', '/blocks'), 'blocks', BlockedUser.fromJson);

  @override
  Future<BlockedUser> createBlock(String userId) async => BlockedUser.fromJson(
    _map(await _request('POST', '/blocks', body: {'user_id': userId})),
  );

  @override
  Future<void> deleteBlock(String userId) async {
    await _request('DELETE', '/blocks/${Uri.encodeComponent(userId)}');
  }

  @override
  Future<void> putDevice(DeviceRegistration registration) async {
    await _request('PUT', '/devices', body: registration.toJson());
  }

  @override
  Future<List<RegularSlot>> getRegularSlots() async => _array(
    await _request('GET', '/regular-slots'),
    'slots',
    RegularSlot.fromJson,
  );

  @override
  Future<List<RegularSlot>> putRegularSlots(List<RegularSlot> slots) async =>
      _array(
        await _request(
          'PUT',
          '/regular-slots',
          body: {'slots': slots.map((slot) => slot.toJson()).toList()},
        ),
        'slots',
        RegularSlot.fromJson,
      );

  @override
  Future<List<HimaTimeSuggestion>> getHimaTimeSuggestions() async => _list(
    _map(await _request('GET', '/suggestions/hima-times'))['suggestions'],
    HimaTimeSuggestion.fromJson,
  );
}
