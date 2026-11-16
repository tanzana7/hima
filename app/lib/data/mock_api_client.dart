import 'dart:async';

import 'api_client.dart';
import 'models/models.dart';

/// In-memory stand-in for the shared API server.
///
/// The data is shaped so the demo flow works end to end: the default mood is
/// `ok`, so a one-tap declare matches けんた (ok × ok), and a knock to him is
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
        Mood.fire,
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
        Mood.fire,
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
        Mood.fire,
        Activity.out,
        null,
        '222222222222222202',
        now.add(const Duration(minutes: 24)),
        durationMin: 30,
      ),
      _freeFriend(
        '111111111111111107',
        'なな',
        Mood.fire,
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
    final me = _summary(_myId, _myName);
    _inbox = [
      Knock(
        id: 'knock-in-1',
        sender: _friends[1].user,
        recipient: me,
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

  /// First time each session pair was matched, so the same pair is not
  /// re-notified after a mood or activity change.
  final Map<String, DateTime> _matchCreatedAt = {};
  final List<_MockMember> _members = [];
  final Set<String> _blockedIds = {};
  final List<RegularSlot> _regularSlots = [];
  UserSettings _settings = const UserSettings(
    autoMode: false,
    autoMood: Mood.ok,
    notifyOnHima: true,
  );
  HimaSession? _myHima;
  int _sessionSequence = 0;
  int _knockSequence = 0;

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
  Future<UserProfile> loginWithDiscord(DiscordAuthRequest? request) async =>
      _profile;

  @override
  Future<void> logout() async {}

  @override
  Future<UserProfile> getMe() async => _profile;

  @override
  Future<UserSettings> updateSettings(UserSettings settings) async {
    _settings = settings;
    return _settings;
  }

  @override
  Future<List<Guild>> getGuilds() async => List.unmodifiable(_guilds);

  @override
  Future<Guild> updateGuildVisibility(String guildId, bool visible) async {
    final index = _guilds.indexWhere((guild) => guild.id == guildId);
    if (index < 0) {
      throw const ApiException(
        statusCode: 404,
        code: 'guild_not_found',
        message: 'サーバーが見つかりません。',
      );
    }
    final updated = Guild(
      id: guildId,
      name: _guilds[index].name,
      visible: visible,
    );
    _guilds[index] = updated;
    return updated;
  }

  @override
  Future<HimaSession?> getMyHima() async => _activeHima;

  HimaSession? get _activeHima {
    final declaration = _myHima;
    if (declaration == null ||
        !declaration.expiresAt.isAfter(DateTime.now().toUtc())) {
      return null;
    }
    return declaration;
  }

  @override
  Future<HimaSession> putMyHima(HimaDeclaration declaration) async {
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
    final session = HimaSession(
      sessionId: current?.sessionId ?? 'session-me-$_sessionSequence',
      user: _summary(_myId, _myName),
      mood: declaration.mood,
      activity: declaration.activity,
      note: declaration.note,
      startedAt: current?.startedAt ?? now,
      expiresAt: now.add(Duration(minutes: declaration.durationMin)),
      durationMin: declaration.durationMin,
      source: current?.source ?? declaration.source,
    );
    _myHima = session;
    // Matches are derived from the current moods in getMatches, so a mood
    // change on the same session takes effect immediately.
    return session;
  }

  /// fire × fire and ok × ok match both sides, fire × ok only the fire side,
  /// and quiet never matches.
  MatchKind? _matchKindFor(Mood mine, Mood other) => switch ((mine, other)) {
    (Mood.fire, Mood.fire) => MatchKind.fireFire,
    (Mood.fire, Mood.ok) => MatchKind.fireOk,
    (Mood.ok, Mood.ok) => MatchKind.okOk,
    _ => null,
  };

  @override
  Future<void> deleteMyHima() async {
    _myHima = null;
  }

  @override
  Future<List<HimaSession>> getHima() async {
    final now = DateTime.now().toUtc();
    final visible = _friends
        .where(
          (friend) =>
              !_isBlocked(friend.user.id) &&
              _isVisible(friend.user.id) &&
              friend.expiresAt.isAfter(now),
        )
        .toList();
    final mine = _activeHima?.activity;
    visible.sort((a, b) {
      final byActivity = activityMatchRank(
        mine,
        a.activity,
      ).compareTo(activityMatchRank(mine, b.activity));
      return byActivity == 0
          ? a.user.displayName.compareTo(b.user.displayName)
          : byActivity;
    });
    return List.unmodifiable(visible);
  }

  @override
  Future<List<FriendServer>> getFriends() async {
    final now = DateTime.now().toUtc();
    return _guilds.map((guild) {
      final members =
          _members
              .where(
                (member) =>
                    member.guildId == guild.id &&
                    !_isBlocked(member.user.id),
              )
              .map((member) {
                final hima = guild.visible
                    ? _friends
                          .where(
                            (friend) =>
                                friend.user.id == member.user.id &&
                                friend.expiresAt.isAfter(now),
                          )
                          .firstOrNull
                    : null;
                return FriendMember(user: member.user, hima: hima);
              })
              .toList()
            ..sort((a, b) {
              if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
              return a.user.displayName.compareTo(b.user.displayName);
            });
      return FriendServer(guild: guild, members: members);
    }).toList(growable: false);
  }

  @override
  Future<List<MatchRecord>> getMatches({DateTime? since}) async {
    final mine = _activeHima;
    if (mine == null) return const [];
    final now = DateTime.now().toUtc();
    final matches = <MatchRecord>[];
    for (final friend in _friends) {
      if (_isBlocked(friend.user.id) || !_isVisible(friend.user.id)) continue;
      if (!friend.expiresAt.isAfter(now)) continue;
      // Derived from the current moods, so changing the mood of a live session
      // adds or removes its match cards immediately.
      final kind = _matchKindFor(mine.mood, friend.mood);
      if (kind == null) continue;
      final createdAt = _matchCreatedAt.putIfAbsent(
        '${mine.sessionId}:${friend.sessionId}',
        () => now,
      );
      if (since != null && !createdAt.isAfter(since.toUtc())) continue;
      matches.add(
        MatchRecord(
          mySessionId: mine.sessionId,
          otherSessionId: friend.sessionId,
          kind: kind,
          otherUser: friend.user,
          otherHima: MatchedHima(
            mood: friend.mood,
            activity: friend.activity,
            note: friend.note,
            expiresAt: friend.expiresAt,
          ),
          createdAt: createdAt,
        ),
      );
    }
    matches.sort((a, b) {
      int rank(MatchRecord match) {
        final friend = _friends
            .where((session) => session.sessionId == match.otherSessionId)
            .firstOrNull;
        return activityMatchRank(mine.activity, friend?.activity);
      }

      final byActivity = rank(a).compareTo(rank(b));
      return byActivity == 0
          ? b.createdAt.compareTo(a.createdAt)
          : byActivity;
    });
    return List.unmodifiable(matches);
  }

  @override
  Future<Knock> createKnock({
    required String userId,
    required KnockTemplate template,
  }) async {
    final friend = _friends.where((item) => item.user.id == userId).firstOrNull;
    // The contract only allows knocking someone who is hima right now; a friend
    // whose declaration expired after the list was fetched is rejected too.
    if (friend == null ||
        _isBlocked(userId) ||
        !_isVisible(userId) ||
        !friend.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const ApiException(
        statusCode: 404,
        code: 'user_not_available',
        message: 'この人にはノックできません。',
      );
    }
    final guildId = _guildOf(userId);
    final guild = _guilds.where((item) => item.id == guildId).firstOrNull;
    if (guild == null) {
      throw const ApiException(
        statusCode: 404,
        code: 'guild_not_found',
        message: 'サーバーが見つかりません。',
      );
    }
    _knockSequence++;
    final knock = Knock(
      id: 'knock-out-$_knockSequence',
      sender: _summary(_myId, _myName),
      recipient: friend.user,
      template: template,
      status: KnockStatus.pending,
      createdAt: DateTime.now().toUtc(),
      guild: GuildSummary(id: guild.id, name: guild.name),
      message: template.text,
      recipientNote: friend.mood == Mood.quiet ? 'スルーしてOK' : null,
    );
    _sent.insert(0, knock);
    // The delayed reply keeps the demo interactive without a push service.
    Timer(const Duration(seconds: 3), () {
      final index = _sent.indexWhere((item) => item.id == knock.id);
      if (index < 0 || _sent[index].status != KnockStatus.pending) return;
      _sent[index] = _copyKnock(
        _sent[index],
        status: KnockStatus.accepted,
        respondedAt: DateTime.now().toUtc(),
      );
    });
    return knock;
  }

  Knock _copyKnock(
    Knock knock, {
    KnockStatus? status,
    DateTime? respondedAt,
    DateTime? resultSeenAt,
    bool clearSeenAt = false,
  }) => Knock(
    id: knock.id,
    sender: knock.sender,
    recipient: knock.recipient,
    template: knock.template,
    status: status ?? knock.status,
    createdAt: knock.createdAt,
    guild: knock.guild,
    message: knock.message,
    respondedAt: respondedAt ?? knock.respondedAt,
    recipientNote: knock.recipientNote,
    resultSeenAt: clearSeenAt ? null : resultSeenAt ?? knock.resultSeenAt,
  );

  @override
  Future<List<Knock>> getKnockInbox() async => List.unmodifiable(
    _inbox.where((knock) => !_isBlocked(knock.sender?.id ?? '')).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Future<List<Knock>> getKnockSent() async => List.unmodifiable(
    _sent.where((knock) => !_isBlocked(knock.recipient?.id ?? '')).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Future<void> respondToKnock(String knockId, KnockStatus response) async {
    if (response == KnockStatus.pending) {
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
    _inbox[index] = _copyKnock(
      _inbox[index],
      status: response,
      respondedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<DateTime?> markKnockResultSeen(String knockId) async {
    final index = _sent.indexWhere((knock) => knock.id == knockId);
    if (index < 0 || _isBlocked(_sent[index].recipient?.id ?? '')) {
      throw const ApiException(
        statusCode: 404,
        code: 'knock_not_found',
        message: 'ノックが見つかりません。',
      );
    }
    final seenAt = DateTime.now().toUtc();
    _sent[index] = _copyKnock(_sent[index], resultSeenAt: seenAt);
    return seenAt;
  }

  @override
  Future<List<BlockedUser>> getBlocks() async => _blockedIds
      .map((id) => _members.where((member) => member.user.id == id).firstOrNull)
      .whereType<_MockMember>()
      .map(
        (member) => BlockedUser(
          user: member.user,
          createdAt: DateTime.now().toUtc(),
        ),
      )
      .toList(growable: false);

  @override
  Future<BlockedUser> createBlock(String userId) async {
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
    return BlockedUser(user: member.user, createdAt: DateTime.now().toUtc());
  }

  @override
  Future<void> deleteBlock(String userId) async {
    _blockedIds.remove(userId);
  }

  @override
  Future<void> putDevice(DeviceRegistration registration) async {}

  @override
  Future<List<RegularSlot>> getRegularSlots() async =>
      List.unmodifiable(_regularSlots);

  @override
  Future<List<RegularSlot>> putRegularSlots(List<RegularSlot> slots) async {
    _regularSlots
      ..clear()
      ..addAll(slots);
    return List.unmodifiable(_regularSlots);
  }

  @override
  Future<List<HimaTimeSuggestion>> getHimaTimeSuggestions() async => const [
    HimaTimeSuggestion(weekday: 5, hour: 20, likelihood: 0.78),
    HimaTimeSuggestion(weekday: 6, hour: 14, likelihood: 0.64),
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
