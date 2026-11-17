import 'models/models.dart';

/// The app's view of the API server (`docs/api-contract.md`).
///
/// The interface follows the server's resources rather than one call per screen:
/// `/app/me` and `/app/board` each answer with one snapshot, so a poll costs two
/// requests instead of one per list.
abstract interface class ApiClient {
  /// Fired when the server rejects the stored token (401). The JWT lasts 30 days
  /// and has no refresh endpoint, so the app has to drop it and sign in again.
  void Function()? get onUnauthorized;
  set onUnauthorized(void Function()? value);

  /// Loads a token saved by a previous launch. True when one was found; the
  /// caller still has to prove it with [getMe].
  Future<bool> restoreToken();

  /// Exchanges a Discord authorization code for the app token.
  ///
  /// A null request is the offline demo login, which only the mock accepts.
  Future<void> loginWithDiscord(DiscordAuthRequest? request);

  /// Clears the token locally. The server has no logout endpoint.
  Future<void> logout();

  Future<MeSnapshot> getMe();
  Future<UserSettings> updateSettings({
    bool? autoMode,
    Mood? autoMood,
    bool? notifyOnHima,
  });
  /// Returns the visibility the server stored.
  Future<bool> updateGuildVisibility(String guildId, bool visible);

  /// `POST /app/sessions`. Declaring again extends the live session.
  Future<void> declareHima(HimaDeclaration declaration);
  Future<void> endHima();

  Future<BoardSnapshot> getBoard();

  /// Every visible member of my shared servers, from `GET /app/members`.
  ///
  /// The rows are flat, so the caller groups them by [ServerMember.guildId]
  /// using the guilds it already has. [guildIds] are the memberships from
  /// `/app/me`: without a `guild_id` the endpoint only answers for the servers
  /// whose own membership is visible, which would drop every member of a server
  /// I hid.
  Future<List<ServerMember>> getMembers(List<String> guildIds);

  Future<Knock> createKnock({
    required UserSummary to,
    required KnockTemplate template,
  });

  /// Knocks I sent, newest first, from `GET /app/knocks/sent`.
  Future<List<Knock>> getSentKnocks();

  Future<void> respondToKnock(String knockId, KnockStatus response);

  /// Marks every unseen reply as seen in one call.
  Future<void> markKnockResultsSeen();

  Future<List<BlockedUser>> getBlocks();
  Future<void> createBlock(String userId);
  Future<void> deleteBlock(String userId);

  Future<void> putDevice(DeviceRegistration registration);
  Future<void> deleteDevice(String fcmToken);

  Future<List<RegularSlot>> getRegularSlots();
  Future<RegularSlot> addRegularSlot(RegularSlot slot);
  Future<void> deleteRegularSlot(String slotId);

  Future<List<HimaTimeSuggestion>> getForecast();
}

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
