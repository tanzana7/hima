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

  /// Members of my shared servers, or null when the server does not implement
  /// `GET /app/members` yet (404).
  Future<List<FriendServer>?> getMembers();

  Future<Knock> createKnock({
    required UserSummary to,
    required KnockTemplate template,
  });

  /// Knocks I sent, or null when the server does not implement
  /// `GET /app/knocks/sent` yet (404).
  Future<List<Knock>?> getSentKnocks();

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
