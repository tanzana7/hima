import 'dart:async';

import 'api_client.dart';
import 'models/models.dart';

/// The declaration the demo panel can stage for me.
enum MockDeclaration {
  /// Not declared.
  none,

  /// Declared for the usual hour.
  live,

  /// Declared and ending in about half a minute, so the home screen's own
  /// countdown runs into the real 「終了したよ」 state.
  endingSoon,
}

/// Which seeded friends the board shows.
enum MockFriends {
  /// Nobody is hima, but the members are still shared.
  none,

  /// The default set.
  defaults,

  /// More than a screenful, so the lists have to scroll.
  many,
}

/// In-memory stand-in for the shared API server.
///
/// It answers the same snapshots as the real server so the app runs offline and
/// the demo flow works end to end: the default mood is `ok`, so a one-tap
/// declare matches every 🙂 friend (ok × ok), and a knock to one of them is
/// answered with 「いいよ！」 a few seconds later without a push service.
///
/// The demo panel edits the same data from inside the running app, so every
/// control here changes only this object; [reset] puts it back.
class MockApiClient implements ApiClient {
  MockApiClient() {
    reset();
  }

  static const _myId = '999999999999999999';
  static const _myName = 'あなた';

  /// The shared servers. The last one is hidden: its members are still listed,
  /// but their hima is not shared.
  static const _guildVisibleOne = '222222222222222201';
  static const _guildVisibleTwo = '222222222222222202';
  static const _guildHidden = '222222222222222203';

  /// About two seconds, the latency the panel's 「遅い通信」 shows.
  static const _slowLatency = Duration(seconds: 2);

  /// The failure every call throws while 「通信エラー」 is on: the app handles
  /// this type as a failed request everywhere.
  static const _unavailable = ApiException(
    statusCode: 503,
    code: 'server_unavailable',
    message: 'サーバーにつながりませんでした。',
  );

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
  UserSettings _settings = UserSettings.fallback;
  HimaSession? _myHima;
  int _sessionSequence = 0;
  int _knockSequence = 0;
  int _slotSequence = 0;

  /// The delayed replies still waiting to fire, by knock id.
  ///
  /// [reset] restarts [_knockSequence], so without cancelling these a knock sent
  /// just before the reset would share its id with a new one and be answered by
  /// the old timer.
  final Map<String, Timer> _pendingReplies = {};

  /// Every call throws [ApiException] while this is on, without changing
  /// anything: the app's own error paths are the state being demonstrated.
  bool failEveryCall = false;

  /// Every call takes [_slowLatency] while this is on.
  bool slowEveryCall = false;

  @override
  void Function()? onUnauthorized;

  /// Never consulted: the mock has no token to reject.
  @override
  bool Function()? keepSessionOnUnauthorized;

  /// Puts every list back to the seeded demo data, including the modes.
  void reset() {
    final now = DateTime.now().toUtc();
    _guilds = [
      const Guild(id: _guildVisibleOne, name: 'いつものメンバー', visible: true),
      const Guild(id: _guildVisibleTwo, name: 'ゲーム仲間', visible: true),
      const Guild(id: _guildHidden, name: '大学の友達', visible: false),
    ];
    _members.clear();
    _friends = _defaultFriends(now);
    // The three members who are not hima, so the 友達 tab has people to list
    // and 「友達がひま宣言」 has someone to turn.
    _addMember('111111111111111108', 'はる', _guildVisibleOne);
    _addMember('111111111111111109', 'そら', _guildVisibleOne);
    _addMember('111111111111111110', 'かんた', _guildHidden);
    _blockedIds
      ..clear()
      // Seeded so the 「マッチングしない人」 list is not empty in the demo.
      ..add('111111111111111106');
    _inbox = [
      Knock(
        id: 'knock-in-1',
        sender: _friends[1].user,
        recipient: _summary(_myId, _myName),
        template: KnockTemplate.game,
        status: KnockStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 2)),
        guild: const GuildSummary(id: _guildVisibleOne, name: 'いつものメンバー'),
        message: KnockTemplate.game.text,
      ),
    ];
    _sent.clear();
    _seenResultIds.clear();
    _regularSlots.clear();
    // The knocks they would answer are gone, and the ids start again at one.
    for (final reply in _pendingReplies.values) {
      reply.cancel();
    }
    _pendingReplies.clear();
    _settings = UserSettings.fallback;
    _myHima = null;
    _sessionSequence = 0;
    _knockSequence = 0;
    _slotSequence = 0;
    failEveryCall = false;
    slowEveryCall = false;
  }

  /// Stages my own declaration without going through the API, so 「もうすぐ
  /// 終わる」 can start a session shorter than the 30 minutes the app offers.
  void setDeclaration(MockDeclaration declaration) {
    _myHima = switch (declaration) {
      MockDeclaration.none => null,
      MockDeclaration.live => _mySession(const Duration(minutes: 60)),
      MockDeclaration.endingSoon => _mySession(const Duration(seconds: 30)),
    };
  }

  /// Replaces the hima friends on the board, keeping the members.
  void setFriends(MockFriends friends) {
    final now = DateTime.now().toUtc();
    _friends = switch (friends) {
      MockFriends.none => [],
      MockFriends.defaults => _defaultFriends(now),
      MockFriends.many => [..._defaultFriends(now), ..._extraFriends(now)],
    };
  }

  /// A knock from a hima friend, or from anyone when nobody is hima.
  void pushIncomingKnock() {
    final sender = _friends.firstOrNull?.user ?? _members.firstOrNull?.user;
    if (sender == null) return;
    final guildId = _guildOf(sender.id);
    final guild = _guilds.where((item) => item.id == guildId).firstOrNull;
    _knockSequence++;
    _inbox = [
      Knock(
        id: 'knock-in-demo-$_knockSequence',
        sender: sender,
        recipient: _summary(_myId, _myName),
        template: KnockTemplate.game,
        status: KnockStatus.pending,
        createdAt: DateTime.now().toUtc(),
        guild: guild == null
            ? null
            : GuildSummary(id: guild.id, name: guild.name),
        message: KnockTemplate.game.text,
      ),
      ..._inbox,
    ];
  }

  /// Turns someone who is not hima into a hima friend, which is what the board
  /// shows as a new card.
  void friendDeclaresHima() {
    final now = DateTime.now().toUtc();
    final himaIds = {for (final friend in _friends) friend.user.id};
    final candidate = _members
        .where(
          (member) =>
              member.user.id != _myId &&
              !himaIds.contains(member.user.id) &&
              !_isBlocked(member.user.id) &&
              // A hidden server shares no hima, so its members would not show.
              _isGuildVisible(member.guildId),
        )
        .firstOrNull;
    if (candidate == null) return;
    _friends = [
      ..._friends,
      _freeFriend(
        candidate.user.id,
        candidate.user.displayName,
        Mood.ok,
        Activity.chat,
        null,
        candidate.guildId,
        now.add(const Duration(minutes: 45)),
      ),
    ];
  }

  /// Stages both sides the home screen derives a match from: a live 🙂
  /// declaration of mine and at least one live 🙂 friend.
  void triggerMatch() {
    final now = DateTime.now().toUtc();
    if (_activeHima == null) setDeclaration(MockDeclaration.live);
    final hasOkFriend = _friends.any(
      (friend) =>
          friend.mood == Mood.ok &&
          friend.expiresAt.isAfter(now) &&
          _isVisible(friend.user.id),
    );
    if (hasOkFriend) return;
    if (_friends.isEmpty) {
      _friends = _defaultFriends(now);
      return;
    }
    final index = _friends.indexWhere(
      (friend) => _isVisible(friend.user.id),
    );
    if (index < 0) return;
    final friend = _friends[index];
    final guildId = _guildOf(friend.user.id);
    if (guildId == null) return;
    _friends[index] = _freeFriend(
      friend.user.id,
      friend.user.displayName,
      Mood.ok,
      friend.activity,
      friend.note,
      guildId,
      now.add(const Duration(minutes: 40)),
    );
  }

  static UserSummary _summary(String id, String name) =>
      UserSummary(id: id, displayName: name);

  void _addMember(String id, String name, String guildId) {
    // Replaced rather than appended so seeding the same person twice (the
    // default friends and 「友達が多い」) cannot duplicate a row.
    _members.removeWhere((member) => member.user.id == id);
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

  /// My own session, built without the API so the panel can pick the length.
  HimaSession _mySession(Duration remaining) {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(remaining);
    final durationMin = remaining.inMinutes >= 60 ? 60 : 30;
    return HimaSession(
      sessionId: 'session-me-demo',
      user: _summary(_myId, _myName),
      mood: Mood.ok,
      activity: Activity.game,
      startedAt: expiresAt.subtract(Duration(minutes: durationMin)),
      expiresAt: expiresAt,
      durationMin: durationMin,
      source: DeclarationSource.manual,
    );
  }

  List<HimaSession> _defaultFriends(DateTime now) => [
    _freeFriend(
      '111111111111111101',
      'さな',
      Mood.ok,
      Activity.game,
      '協力プレイしたい！',
      _guildVisibleOne,
      now.add(const Duration(minutes: 42)),
    ),
    _freeFriend(
      '111111111111111102',
      'けんた',
      Mood.ok,
      Activity.game,
      null,
      _guildVisibleOne,
      now.add(const Duration(minutes: 28)),
    ),
    // No activity chosen: the UI must show a plain 「ひま」.
    _freeFriend(
      '111111111111111103',
      'みお',
      Mood.quiet,
      null,
      '聞き専でもよければ',
      _guildVisibleOne,
      now.add(const Duration(minutes: 19)),
      durationMin: 30,
    ),
    _freeFriend(
      '111111111111111104',
      'りく',
      Mood.quiet,
      Activity.chat,
      null,
      _guildVisibleTwo,
      now.add(const Duration(minutes: 55)),
      durationMin: 120,
    ),
    _freeFriend(
      '111111111111111105',
      'あき',
      Mood.ok,
      Activity.any,
      '今日はゆっくり',
      _guildVisibleTwo,
      now.add(const Duration(minutes: 36)),
    ),
    _freeFriend(
      '111111111111111106',
      'ゆず',
      Mood.quiet,
      Activity.out,
      null,
      _guildVisibleTwo,
      now.add(const Duration(minutes: 24)),
      durationMin: 30,
    ),
    _freeFriend(
      '111111111111111107',
      'なな',
      Mood.ok,
      Activity.work,
      null,
      _guildHidden,
      now.add(const Duration(minutes: 33)),
    ),
  ];

  /// The names 「友達が多い」 adds, so the grid and the 友達 tab scroll past one
  /// screen.
  static const _extraFriendNames = [
    'ゆい',
    'そうた',
    'ひなた',
    'はると',
    'めい',
    'りん',
    'かえで',
    'つむぎ',
    'あおい',
    'ゆうき',
  ];

  List<HimaSession> _extraFriends(DateTime now) => [
    for (var index = 0; index < _extraFriendNames.length; index++)
      _freeFriend(
        '1111111111111112${index.toString().padLeft(2, '0')}',
        _extraFriendNames[index],
        index.isEven ? Mood.ok : Mood.quiet,
        Activity.values[index % Activity.values.length],
        null,
        index.isEven ? _guildVisibleOne : _guildVisibleTwo,
        now.add(Duration(minutes: 20 + index * 3)),
      ),
  ];

  String? _guildOf(String userId) =>
      _members.where((member) => member.user.id == userId).firstOrNull?.guildId;

  bool _isGuildVisible(String guildId) =>
      _guilds.any((guild) => guild.id == guildId && guild.visible);

  bool _isVisible(String userId) {
    final guildId = _guildOf(userId);
    if (guildId == null) return false;
    return _isGuildVisible(guildId);
  }

  bool _isBlocked(String userId) => _blockedIds.contains(userId);

  UserProfile get _profile =>
      UserProfile(id: _myId, displayName: _myName, settings: _settings);

  /// The gate every call goes through, so the panel's switches exercise the
  /// app's own loading and error paths instead of one chosen screen. It runs
  /// before anything is read or written, so a failing call changes nothing.
  Future<void> _gate() async {
    if (slowEveryCall) await Future<void>.delayed(_slowLatency);
    if (failEveryCall) throw _unavailable;
  }

  @override
  Future<bool> restoreToken() async {
    await _gate();
    return false;
  }

  @override
  Future<void> loginWithDiscord(DiscordAuthRequest? request) async {
    await _gate();
  }

  @override
  Future<void> logout() async {
    await _gate();
  }

  @override
  Future<MeSnapshot> getMe() async {
    await _gate();
    return MeSnapshot(
      profile: _profile,
      session: _activeHima,
      guilds: List.unmodifiable(_guilds),
    );
  }

  @override
  Future<UserSettings> updateSettings({
    bool? autoMode,
    Mood? autoMood,
  }) async {
    await _gate();
    _settings = _settings.copyWith(autoMode: autoMode, autoMood: autoMood);
    return _settings;
  }

  @override
  Future<bool> updateGuildVisibility(String guildId, bool visible) async {
    await _gate();
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
  Future<DateTime> declareHima(HimaDeclaration declaration) async {
    await _gate();
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
    final expiresAt = now.add(Duration(minutes: declaration.durationMin));
    _myHima = HimaSession(
      sessionId: current?.sessionId ?? 'session-me-$_sessionSequence',
      user: _summary(_myId, _myName),
      mood: declaration.mood,
      activity: declaration.activity,
      note: declaration.note,
      // An extend keeps the original start, like the server does.
      startedAt: current?.startedAt ?? now,
      expiresAt: expiresAt,
      durationMin: declaration.durationMin,
      source: current?.source ?? declaration.source,
    );
    return expiresAt;
  }

  @override
  Future<void> endHima() async {
    await _gate();
    _myHima = null;
  }

  @override
  Future<BoardSnapshot> getBoard() async {
    await _gate();
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
  Future<List<ServerMember>> getMembers(List<String> guildIds) async {
    await _gate();
    return [
      for (final member in _members)
        if (guildIds.contains(member.guildId))
          ServerMember(user: member.user, guildId: member.guildId),
    ];
  }

  @override
  Future<Knock> createKnock({
    required UserSummary to,
    required KnockTemplate template,
  }) async {
    await _gate();
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
    _scheduleReply(knock.id);
    return knock;
  }

  /// The delayed reply that keeps the demo interactive without a push service.
  ///
  /// It is kept by id so `reset()` can cancel it: the reset restarts the knock
  /// ids, and a timer left over from before it would answer the new knock with
  /// its own id three seconds early.
  void _scheduleReply(String knockId) {
    _pendingReplies.remove(knockId)?.cancel();
    _pendingReplies[knockId] = Timer(const Duration(seconds: 3), () {
      _pendingReplies.remove(knockId);
      final index = _sent.indexWhere((item) => item.id == knockId);
      if (index < 0 || _sent[index].status != KnockStatus.pending) return;
      _sent[index] = _sent[index].copyWith(
        status: KnockStatus.accepted,
        respondedAt: DateTime.now().toUtc(),
      );
    });
  }

  @override
  Future<List<Knock>> getSentKnocks() async {
    await _gate();
    return List.unmodifiable(
      _sent.where((knock) => !_isBlocked(knock.recipient?.id ?? '')).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  @override
  Future<void> respondToKnock(String knockId, KnockStatus response) async {
    await _gate();
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
    await _gate();
    for (final knock in _sent) {
      if (knock.status == KnockStatus.pending) continue;
      _seenResultIds.add(knock.id);
    }
  }

  @override
  Future<List<BlockedUser>> getBlocks() async {
    await _gate();
    return _blockedIds
        .map((id) => _members.where((member) => member.user.id == id).firstOrNull)
        .whereType<_MockMember>()
        .map((member) => BlockedUser(user: member.user))
        .toList(growable: false);
  }

  @override
  Future<void> createBlock(String userId) async {
    await _gate();
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
    await _gate();
    _blockedIds.remove(userId);
  }

  @override
  Future<void> putDevice(DeviceRegistration registration) async {
    await _gate();
  }

  @override
  Future<void> deleteDevice(String fcmToken) async {
    await _gate();
  }

  @override
  Future<List<RegularSlot>> getRegularSlots() async {
    await _gate();
    return List.unmodifiable(_regularSlots);
  }

  @override
  Future<RegularSlot> addRegularSlot(RegularSlot slot) async {
    await _gate();
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
    await _gate();
    _regularSlots.removeWhere((slot) => slot.id == slotId);
  }

  /// Built from the regular slots by merging the ranges of each day, the way
  /// the server's forecast does, so editing よくひまな時間 changes the times the
  /// 自動ひま提案 card is fed in the demo too.
  @override
  Future<List<HimaTimeSuggestion>> getForecast() async {
    await _gate();
    final byDay = <int, List<RegularSlot>>{};
    for (final slot in _regularSlots) {
      (byDay[slot.weekday] ??= []).add(slot);
    }
    final forecast = <HimaTimeSuggestion>[];
    for (final entry in byDay.entries) {
      final slots = [...entry.value]
        ..sort((a, b) => a.startMin.compareTo(b.startMin));
      var start = slots.first.startMin;
      var end = slots.first.endMin;
      for (final slot in slots.skip(1)) {
        if (slot.startMin <= end) {
          if (slot.endMin > end) end = slot.endMin;
          continue;
        }
        forecast.add(_suggestion(entry.key, start, end));
        start = slot.startMin;
        end = slot.endMin;
      }
      forecast.add(_suggestion(entry.key, start, end));
    }
    forecast.sort(
      (a, b) => a.weekday == b.weekday
          ? a.startMin.compareTo(b.startMin)
          : a.weekday.compareTo(b.weekday),
    );
    return forecast;
  }

  /// A range that only comes from the slots I registered: the mock has no
  /// declaration history to weigh it against.
  static HimaTimeSuggestion _suggestion(int weekday, int startMin, int endMin) =>
      HimaTimeSuggestion(
        weekday: weekday,
        startMin: startMin,
        endMin: endMin,
        basis: 'manual',
        score: 0,
        days: 0,
      );
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
