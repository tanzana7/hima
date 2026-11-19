import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models/models.dart';
import 'token_store.dart';

/// Talks to the real API server (`docs/api-contract.md`).
///
/// Every id is a JSON number on the wire and a String in the app, and the mood
/// vocabulary differs (`moon` is the app's `Mood.quiet`); both conversions happen
/// here and in `models.dart`, never in the UI.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    required String baseUrl,
    http.Client? client,
    TokenStore tokenStore = const TokenStore(),
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
       _client = client ?? http.Client(),
       _tokenStore = tokenStore;

  final String _baseUrl;
  final http.Client _client;
  final TokenStore _tokenStore;

  String? _token;

  @override
  void Function()? onUnauthorized;

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers['Accept'] = 'application/json';
    // A free ngrok tunnel answers browser-like clients with an HTML interstitial
    // instead of proxying the request. The header opts out of it and is ignored
    // by any other host.
    request.headers['ngrok-skip-browser-warning'] = '1';
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
    if (response.statusCode == 401 && authenticated) {
      // The token expired or was revoked and there is no refresh endpoint, so
      // drop it and tell the app to go back to the login screen.
      _token = null;
      await _tokenStore.clear();
      onUnauthorized?.call();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _error(response);
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    return decodeJson(response.body);
  }

  /// FastAPI reports failures as `{"detail": ...}`, where `detail` is a string
  /// for `HTTPException` and a list of `{loc, msg}` objects for 422 validation
  /// errors.
  ApiException _error(http.Response response) {
    var detail = '';
    if (response.body.isNotEmpty) {
      try {
        final value = readJsonMap(decodeJson(response.body))['detail'];
        if (value is String) {
          detail = value;
        } else if (value is List && value.isNotEmpty) {
          detail = readOptionalString(readJsonMap(value.first), 'msg') ?? '';
        }
      } on FormatException {
        // A proxy (ngrok interstitial, HTML error page) returned a non-JSON body.
      }
    }
    return ApiException(
      statusCode: response.statusCode,
      code: detail.isEmpty ? 'http_${response.statusCode}' : detail,
      message: _friendlyMessage(response.statusCode),
    );
  }

  /// What the UI shows. The server's `detail` is English and meant for
  /// diagnosis, so it is kept in [ApiException.code] instead.
  static String _friendlyMessage(int statusCode) => switch (statusCode) {
    400 || 422 => '入力内容を確認してね',
    401 => 'ログインし直してね',
    403 => 'この相手にはできないよ',
    404 => '見つからなかったよ',
    409 => 'さっきさそったばかりだよ、少し待ってね',
    _ => '通信に失敗したよ。もう一度試してね',
  };

  JsonMap _map(Object? value) => readJsonMap(value);

  List<T> _array<T>(Object? value, String key, T Function(JsonMap) fromJson) =>
      readModelList(_map(value)[key], fromJson);

  /// Ids travel as JSON numbers, so a String id has to be converted back.
  static int _idAsNumber(String id) => int.parse(id);

  @override
  Future<bool> restoreToken() async {
    final token = await _tokenStore.read();
    _token = token;
    return token != null;
  }

  @override
  Future<void> loginWithDiscord(DiscordAuthRequest? request) async {
    if (request == null) {
      throw StateError('Discord OAuth is required when talking to the API.');
    }
    final response = _map(
      await _request(
        'POST',
        '/auth/discord',
        body: request.toJson(),
        authenticated: false,
      ),
    );
    final token = readString(response, 'token');
    _token = token;
    await _tokenStore.write(token);
  }

  @override
  Future<void> logout() async {
    _token = null;
    await _tokenStore.clear();
  }

  @override
  Future<MeSnapshot> getMe() async {
    final json = _map(await _request('GET', '/app/me'));
    final profile = UserProfile.fromJson(json);
    final session = json['session'];
    return MeSnapshot(
      profile: profile,
      session: session == null
          ? null
          : HimaSession.fromJson(readJsonMap(session), owner: profile.summary),
      guilds: readModelList(json['memberships'], Guild.fromJson),
    );
  }

  @override
  Future<UserSettings> updateSettings({
    bool? autoMode,
    Mood? autoMood,
  }) async {
    // The endpoint takes a partial update, so only the changed keys are sent.
    final autoMoodValue = autoMood == null ? null : moodToJson(autoMood);
    final body = <String, Object?>{
      'auto_mode': ?autoMode,
      'auto_mood': ?autoMoodValue,
    };
    return UserSettings.fromJson(
      _map(await _request('PUT', '/app/me/settings', body: body)),
    );
  }

  @override
  Future<bool> updateGuildVisibility(String guildId, bool visible) async {
    final json = _map(
      await _request(
        'PUT',
        '/app/memberships/${Uri.encodeComponent(guildId)}/visibility',
        body: {'visible': visible},
      ),
    );
    return readBool(json, 'visible');
  }

  @override
  Future<DateTime> declareHima(HimaDeclaration declaration) async {
    // `{session_id, created, expires_at}`. The expiry is handed back instead of
    // being re-read from /app/me, so a declaration that succeeded is never lost
    // when the following read fails.
    final json = _map(
      await _request('POST', '/app/sessions', body: declaration.toJson()),
    );
    return readDateTime(json, 'expires_at');
  }

  @override
  Future<void> endHima() async {
    await _request('DELETE', '/app/sessions');
  }

  @override
  Future<BoardSnapshot> getBoard() async {
    final json = _map(await _request('GET', '/app/board'));
    return BoardSnapshot(
      sessions: readModelList(json['sessions'], HimaSession.fromJson),
      inbox: readModelList(json['inbox'], Knock.fromInboxJson),
      results: readModelList(json['results'], Knock.fromResultJson),
    );
  }

  @override
  Future<List<ServerMember>> getMembers(List<String> guildIds) async {
    // One call per membership: the endpoint without a `guild_id` only answers
    // for the servers whose own membership is visible, so a server I hid would
    // lose every member. The contract answers 404 only when I am not a member of
    // the guild, which `/app/me` just listed.
    final responses = await Future.wait([
      for (final guildId in guildIds)
        _request(
          'GET',
          '/app/members?guild_id=${Uri.encodeComponent(guildId)}',
        ),
    ]);
    return [
      for (final response in responses)
        ..._array(response, 'members', ServerMember.fromJson),
    ];
  }

  @override
  Future<Knock> createKnock({
    required UserSummary to,
    required KnockTemplate template,
  }) async {
    final json = _map(
      await _request(
        'POST',
        '/app/knocks',
        body: {
          'to_user': _idAsNumber(to.id),
          // `knocks.template` stores the invitation text itself, not a key.
          'template': template.text,
        },
      ),
    );
    return Knock(
      id: readId(json, 'id'),
      recipient: to,
      template: template,
      status: knockStatusFromJson(readString(json, 'status')),
      createdAt: DateTime.now().toUtc(),
      message: template.text,
    );
  }

  @override
  Future<List<Knock>> getSentKnocks() async => _array(
    await _request('GET', '/app/knocks/sent'),
    'knocks',
    Knock.fromSentJson,
  );

  @override
  Future<void> respondToKnock(String knockId, KnockStatus response) async {
    // The responder is taken from the JWT, so only the action is accepted here.
    await _request(
      'POST',
      '/app/knocks/${Uri.encodeComponent(knockId)}/reply',
      body: {'action': knockReplyAction(response)},
    );
  }

  @override
  Future<void> markKnockResultsSeen() async {
    await _request('POST', '/app/knocks/results/seen');
  }

  @override
  Future<List<BlockedUser>> getBlocks() async => _array(
    await _request('GET', '/app/blocks'),
    'blocked_users',
    BlockedUser.fromJson,
  );

  @override
  Future<void> createBlock(String userId) async {
    await _request(
      'POST',
      '/app/blocks',
      body: {'blocked_user_id': _idAsNumber(userId)},
    );
  }

  @override
  Future<void> deleteBlock(String userId) async {
    // `DELETE /app/blocks` takes the target in the body, not in the path.
    await _request(
      'DELETE',
      '/app/blocks',
      body: {'blocked_user_id': _idAsNumber(userId)},
    );
  }

  @override
  Future<void> putDevice(DeviceRegistration registration) async {
    await _request('POST', '/app/devices', body: registration.toJson());
  }

  @override
  Future<void> deleteDevice(String fcmToken) async {
    await _request('DELETE', '/app/devices', body: {'fcm_token': fcmToken});
  }

  @override
  Future<List<RegularSlot>> getRegularSlots() async =>
      _array(await _request('GET', '/app/regular-slots'), 'slots',
          RegularSlot.fromJson);

  @override
  Future<RegularSlot> addRegularSlot(RegularSlot slot) async =>
      RegularSlot.fromJson(
        _map(await _request('POST', '/app/regular-slots', body: slot.toJson())),
      );

  @override
  Future<void> deleteRegularSlot(String slotId) async {
    await _request(
      'DELETE',
      '/app/regular-slots/${Uri.encodeComponent(slotId)}',
    );
  }

  @override
  Future<List<HimaTimeSuggestion>> getForecast() async => _array(
    await _request('GET', '/app/free-time/forecast'),
    'slots',
    HimaTimeSuggestion.fromJson,
  );
}
