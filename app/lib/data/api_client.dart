import 'models/models.dart';

abstract interface class ApiClient {
  Future<UserProfile> loginWithDiscord(DiscordAuthRequest? request);
  Future<void> logout();
  Future<UserProfile> getMe();
  Future<UserSettings> updateSettings(UserSettings settings);
  Future<List<Guild>> getGuilds();
  Future<Guild> updateGuildVisibility(String guildId, bool visible);
  Future<HimaSession?> getMyHima();
  Future<HimaSession> putMyHima(HimaDeclaration declaration);
  Future<void> deleteMyHima();
  Future<List<HimaSession>> getHima();
  Future<List<FriendServer>> getFriends();
  Future<List<MatchRecord>> getMatches({DateTime? since});
  Future<Knock> createKnock({
    required String userId,
    required KnockTemplate template,
  });
  Future<List<Knock>> getKnockInbox();
  Future<List<Knock>> getKnockSent();
  Future<void> respondToKnock(String knockId, KnockStatus response);
  Future<DateTime?> markKnockResultSeen(String knockId);
  Future<List<BlockedUser>> getBlocks();
  Future<BlockedUser> createBlock(String userId);
  Future<void> deleteBlock(String userId);
  Future<void> putDevice(DeviceRegistration registration);
  Future<List<RegularSlot>> getRegularSlots();
  Future<List<RegularSlot>> putRegularSlots(List<RegularSlot> slots);
  Future<List<HimaTimeSuggestion>> getHimaTimeSuggestions();
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
