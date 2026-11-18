import 'dart:async';

import 'api_client.dart';
import 'models/models.dart';

/// In-memory stand-in for the shared API server.
///
/// It answers the same snapshots as the real server so the app runs offline and
/// the demo flow works end to end: the default mood is `ok`, so a one-tap
/// declare matches every 🙂 friend (ok × ok), and a knock to one of them is
/// answered with 「いいよ！」 a few seconds later without a push service.
class MockApiClient implements ApiClient {
  MockApiClient() {
    final now = DateTime.now().toUtc();
    _guilds = [
      const Guild(
        id: '222222222222222201',
        name: 'いつものメンバー',
        visible: true,
      ),
      const Guild(id: '222222222222222202', name: 'ゲーム仲間', visible: true),
      // Visibility off: members are still listed, but their hima is not shared.
      const Guild(id: '222222222222222203', name: '大学の友達', visible: false),
    ];
    _friends = [
      _freeFriend(
        '111111111111111101',
        'さな',
        Mood.ok,
        Activity.game,
        '協力プレイしたい！',
        '222222222222222201',
        now.add(const Duration(minutes: 42)),
      ),
      _freeFriend(
        '111111111111111102',
        'けんた',
        Mood.ok,
        Activity.game,
        null,
        '222222222222222201',
        now.add(const Duration(minutes: 28)),
      ),
      // No activity chosen: the UI must show a plain 「ひま」.
      _freeFriend(
        '111111111111111103',
        'みお',
        Mood.quiet,
        null,
        '聞き専でもよければ',
        '222222222222222201',
        now.add(const Duration(minutes: 19)),
        durationMin: 30,
      ),
      _freeFriend(
        '111111111111111104',
        'りく',
        Mood.quiet,
        Activity.chat,
        null,
        '222222222222222202',
        now.add(const Duration(minutes: 55)),
        durationMin: 120,
      ),
      _freeFriend(
        '111111111111111105',
        'あき',
        Mood.ok,
        Activity.any,
        '今日はゆっくり',
        '222222222222222202',
        now.add(const Duration(minutes: 36)),
      ),
      _freeFriend(
        '111111111111111106',
        'ゆず',
        Mood.quiet,
        Activity.out,
        null,
        '222222222222222202',
        now.add(const Duration(minutes: 24)),
        durationMin: 30,
      ),
      _freeFriend(
        '111111111111111107',
        'なな',
        Mood.ok,
        Activity.work,
        null,
        '222222222222222203',
        now.add(const Duration(minutes: 33)),
      ),
    ];
    _addMember('111111111111111108', 'はる', '222222222222222201');
    _addMember('111111111111111109', 'そら', '222222222222222201');
    _addMember('111111111111111110', 'かんた', '222222222222222203');
    // Seeded so the 「マッチングしない人」 list is not empty in the demo.
    _blockedIds.add('111111111111111106');
    _inbox = [
      Knock(
        id: 'knock-in-1',
        sender: _friends[1].user,
        recipient: _summary(_myId, _myName),
        template: KnockTemplate.game,
        status: KnockStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 2)),
        guild: const GuildSummary(
          id: '222222222222222201',
          name: 'いつものメンバー',
        ),
        message: KnockTemplate.game.text,
      ),
    ];
  }

  static const _myId = '999999999999999999';
  static const _myName = 'あなた';

  late List<HimaSession> _friends;
  late List<Guild> _guilds;
  late List<Knock> _inbox;
  final List<Knock> _sent = [];

  final List<_MockMember> _members = [];
  final Set<String> _blockedIds = {};

  /// The mock server's `knocks.result_seen_at`: only the board's unseen
  /// `results` expose it, exactly like the real endpoint.
  final Set<String> _seenResultIds = {};
  final List<RegularSlot> _regularSlots = [];
  UserSettings _settings = const UserSettings(
    autoMode: false,
    autoMood: Mood.ok,
    notifyOnHima: true,
  );
  HimaSession? _myHima;
  int _sessionSequence = 0;
  int _knockSequence = 0;
  int _slotSequence = 0;

  @override
  void Function()? onUnauthorized;

  static UserSummary _summary(String id, String name) =>
      UserSummary(id: id, displayName: name);

  void _addMember(String id, String name, String guildId) {
    _members.add(_MockMember(user: _summary(id, name), guildId: guildId));
  }

  HimaSession _freeFriend(
    String id,
    String name,
    Mood mood,
    Activity? activity,
    String? note,
    String guildId,
    DateTime expiresAt, {
    int durationMin = 60,
  }) {
    _addMember(id, name, guildId);
    // started_at is derived from the allowed duration so the seeded session
    // still satisfies the 30 / 60 / 120 contract while keeping the remaining
    // time short enough for the demo.
    final startedAt = expiresAt.subtract(Duration(minutes: durationMin));
    return HimaSession(
      sessionId: 'session-$id',
      user: _summary(id, name),
      mood: mood,
      activity: activity,
      note: note,
      startedAt: startedAt,
      expiresAt: expiresAt,
      durationMin: durationMin,
      guildIds: [guildId],
    );
  }

  String? _guildOf(String userId) =>
      _members.where((member) => member.user.id == userId).firstOrNull?.guildId;

  bool _isVisible(String userId) {
    final guildId = _guildOf(userId);
    if (guildId == null) return false;
    return _guilds.any((guild) => guild.id == guildId && guild.visible);
  }

  bool _isBlocked(String userId) => _blockedIds.contains(userId);

  UserProfile get _profile =>
      UserProfile(id: _myId, displayName: _myName, settings: _settings);

  @override
  Future<bool> restoreToken() async => false;

  @override
  Future<void> loginWithDiscord(DiscordAuthRequest? request) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<MeSnapshot> getMe() async => MeSnapshot(
    profile: _profile,
    session: _activeHima,
    guilds: List.unmodifiable(_guilds),
  );

  @override
  Future<UserSettings> updateSettings({
    bool? autoMode,
    Mood? autoMood,
    bool? notifyOnHima,
  }) async {
    _settings = _settings.copyWith(
      autoMode: autoMode,
      autoMood: autoMood,
      notifyOnHima: notifyOnHima,
    );
    return _settings;
  }

  @override
  Future<bool> updateGuildVisibility(String guildId, bool visible) async {
    final index = _guilds.indexWhere((guild) => guild.id == guildId);
    if (index < 0) {
      throw const ApiException(
        statusCode: 404,
        code: 'guild_not_found',
        message: 'サーバーが見つかりません。',
      );
    }
    _guilds[index] = _guilds[index].withVisibility(visible);
    return visible;
  }

  HimaSession? get _activeHima {
    final declaration = _myHima;
    if (declaration == null ||
        !declaration.expiresAt.isAfter(DateTime.now().toUtc())) {
      return null;
    }
    return declaration;
  }

  @override
  Future<void> declareHima(HimaDeclaration declaration) async {
    if (!himaDurationChoices.contains(declaration.durationMin)) {
      throw const ApiException(
        statusCode: 400,
        code: 'validation_error',
        message: '入力内容を確認してください。',
      );
    }
    final now = DateTime.now().toUtc();
    final current = _activeHima;
    final isNewSession = current == null;
    if (isNewSession) _sessionSequence++;
    _myHima = HimaSession(
      sessionId: current?.sessionId ?? 'session-me-$_sessionSequence',
      user: _summary(_myId, _myName),
      mood: declaration.mood,
      activity: declaration.activity,
      note: declaration.note,
      // An extend keeps the original start, like the server does.
      startedAt: current?.startedAt ?? now,
      expiresAt: now.add(Duration(minutes: declaration.durationMin)),
      durationMin: declaration.durationMin,
      source: current?.source ?? declaration.source,
    );
  }

  @override
  Future<void> endHima() async {
    _myHima = null;
  }

  @override
  Future<BoardSnapshot> getBoard() async {
    final now = DateTime.now().toUtc();
    final sessions = _friends
        .where(
          (friend) =>
              !_isBlocked(friend.user.id) &&
              _isVisible(friend.user.id) &&
              friend.expiresAt.isAfter(now),
        )
        .toList();
    return BoardSnapshot(
      sessions: List.unmodifiable(sessions),
      inbox: List.unmodifiable(
        _inbox
            .where((knock) => !_isBlocked(knock.sender?.id ?? ''))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      ),
      results: List.unmodifiable(
        _sent
            .where(
              (knock) =>
                  knock.status != KnockStatus.pending &&
                  !_seenResultIds.contains(knock.id) &&
                  !_isBlocked(knock.recipient?.id ?? ''),
            )
            .toList(),
      ),
    );
  }

  @override
  Future<List<ServerMember>> getMembers(List<String> guildIds) async => [
    for (final member in _members)
      if (guildIds.contains(member.guildId))
        ServerMember(user: member.user, guildId: member.guildId),
  ];

  @override
  Future<Knock> createKnock({
    required UserSummary to,
    required KnockTemplate template,
  }) async {
    final friend = _friends
        .where((item) => item.user.id == to.id)
        .firstOrNull;
    // The contract only allows knocking someone who is hima right now; a friend
    // whose declaration expired after the list was fetched is rejected too.
    if (friend == null ||
        _isBlocked(to.id) ||
        !_isVisible(to.id) ||
        !friend.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const ApiException(
        statusCode: 404,
        code: 'user_not_available',
        message: 'この人にはノックできません。',
      );
    }
    final guildId = _guildOf(to.id);
    final guild = _guilds.where((item) => item.id == guildId).firstOrNull;
    _knockSequence++;
    final knock = Knock(
      id: 'knock-out-$_knockSequence',
      sender: _summary(_myId, _myName),
      recipient: to,
      template: template,
      status: KnockStatus.pending,
      createdAt: DateTime.now().toUtc(),
      guild: guild == null ? null : GuildSummary(id: guild.id, name: guild.name),
      message: template.text,
      recipientNote: friend.mood == Mood.quiet ? 'スルーしてOK' : null,
    );
    _sent.insert(0, knock);
    // The delayed reply keeps the demo interactive without a push service.
    Timer(const Duration(seconds: 3), () {
      final index = _sent.indexWhere((item) => item.id == knock.id);
      if (index < 0 || _sent[index].status != KnockStatus.pending) return;
      _sent[index] = _sent[index].copyWith(
        status: KnockStatus.accepted,
        respondedAt: DateTime.now().toUtc(),
      );
    });
    return knock;
  }

  @override
  Future<List<Knock>> getSentKnocks() async => List.unmodifiable(
    _sent.where((knock) => !_isBlocked(knock.recipient?.id ?? '')).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Future<void> respondToKnock(String knockId, KnockStatus response) async {
    if (response == KnockStatus.pending || response == KnockStatus.expired) {
      throw const FormatException(
        'A reply must be accepted, later, or passed.',
      );
    }
    final index = _inbox.indexWhere((knock) => knock.id == knockId);
    if (index < 0 || _isBlocked(_inbox[index].sender?.id ?? '')) {
      throw const ApiException(
        statusCode: 404,
        code: 'knock_not_found',
        message: 'ノックが見つかりません。',
      );
    }
    _inbox[index] = _inbox[index].copyWith(
      status: response,
      respondedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> markKnockResultsSeen() async {
    for (final knock in _sent) {
      if (knock.status == KnockStatus.pending) continue;
      _seenResultIds.add(knock.id);
    }
  }

  @override
  Future<List<BlockedUser>> getBlocks() async => _blockedIds
      .map((id) => _members.where((member) => member.user.id == id).firstOrNull)
      .whereType<_MockMember>()
      .map((member) => BlockedUser(user: member.user))
      .toList(growable: false);

  @override
  Future<void> createBlock(String userId) async {
    final member = _members
        .where((item) => item.user.id == userId)
        .firstOrNull;
    if (member == null) {
      throw const ApiException(
        statusCode: 404,
        code: 'user_not_found',
        message: 'ユーザーが見つかりません。',
      );
    }
    _blockedIds.add(userId);
    _sent.removeWhere(
      (knock) =>
          knock.status == KnockStatus.pending && knock.recipient?.id == userId,
    );
    _inbox.removeWhere(
      (knock) =>
          knock.status == KnockStatus.pending && knock.sender?.id == userId,
    );
  }

  @override
  Future<void> deleteBlock(String userId) async {
    _blockedIds.remove(userId);
  }

  @override
  Future<void> putDevice(DeviceRegistration registration) async {}

  @override
  Future<void> deleteDevice(String fcmToken) async {}

  @override
  Future<List<RegularSlot>> getRegularSlots() async =>
      List.unmodifiable(_regularSlots);

  @override
  Future<RegularSlot> addRegularSlot(RegularSlot slot) async {
    _slotSequence++;
    final saved = RegularSlot(
      id: 'slot-$_slotSequence',
      weekday: slot.weekday,
      startMin: slot.startMin,
      endMin: slot.endMin,
    );
    _regularSlots.add(saved);
    return saved;
  }

  @override
  Future<void> deleteRegularSlot(String slotId) async {
    _regularSlots.removeWhere((slot) => slot.id == slotId);
  }

  @override
  Future<List<HimaTimeSuggestion>> getForecast() async => const [
    HimaTimeSuggestion(
      weekday: 5,
      startMin: 20 * 60,
      endMin: 21 * 60 + 30,
      basis: 'history',
      score: 0.78,
      days: 6,
    ),
    HimaTimeSuggestion(
      weekday: 6,
      startMin: 14 * 60,
      endMin: 15 * 60,
      basis: 'manual',
      score: 0,
      days: 0,
    ),
  ];
}

class _MockMember {
  const _MockMember({required this.user, required this.guildId});

  final UserSummary user;
  final String guildId;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
