import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/hima_suggest_bridge.dart';
import '../data/models/models.dart';

class AppViewModel extends ChangeNotifier {
  AppViewModel(this._api, this._bridge) {
    // The client reports any 401 here: the JWT cannot be refreshed, so the only
    // recovery is to drop it and show the login screen again.
    _api.onUnauthorized = _handleUnauthorized;
  }

  final ApiClient _api;

  /// The native 「自動ひま提案」 worker. It only suggests, so everything sent
  /// here is a mirror of what the server already holds.
  final HimaSuggestBridge _bridge;

  Timer? _pollTimer;
  bool _isAuthenticated = false;
  bool _isBusy = false;
  bool _isRefreshingLive = false;
  bool _liveError = false;

  /// Bumped after every successful mutation and when the session ends. A live
  /// poll captures this value when it starts and throws its results away if it
  /// changed meanwhile: a read that began before a mutation must never overwrite
  /// what the mutation wrote, and a poll started in the session being ended must
  /// not repopulate the signed-out model.
  int _stateGeneration = 0;

  /// Set when a refresh is requested while one is already running, so the
  /// request runs after the in-flight pass instead of being dropped.
  bool _refreshQueued = false;
  UserProfile? _me;
  HimaSession? _myHima;
  List<HimaSession> _boardSessions = [];
  List<HimaSession> _friends = [];
  List<FriendServer> _friendServers = [];

  /// Every visible member of my shared servers, from `GET /app/members`.
  ///
  /// The endpoint is flat, so the server name and its visibility come from
  /// [_guilds] and the grouping happens in [_rebuildFriendServers]; keeping the
  /// raw rows means a poll can re-attach each member's hima without re-reading
  /// the list.
  List<ServerMember> _memberServers = [];
  List<MatchRecord> _matches = [];
  List<Knock> _inbox = [];
  List<Knock> _sent = [];
  List<Guild> _guilds = [];
  List<BlockedUser> _blocks = [];
  List<RegularSlot> _regularSlots = [];
  List<HimaTimeSuggestion> _suggestions = [];

  /// Replies that arrived and have not been shown yet, oldest first.
  ///
  /// `/app/board` returns every unseen reply at once and the server marks them
  /// seen in one bulk call, so the celebration overlay pops this queue one item
  /// at a time instead of asking the server again per id.
  final List<Knock> _resultQueue = [];

  /// First time each session pair was matched, so the same pair is not
  /// re-notified after a mood or activity change.
  final Map<String, DateTime> _matchCreatedAt = {};

  // Remembered between declarations so a single tap can declare again without
  // asking a question. `auto_mood` in settings is only written for compatibility
  // with the server and must not be reused here.
  Mood _lastMood = Mood.ok;
  Activity? _pendingActivity;
  int _durationMin = defaultHimaDurationMin;

  /// True once the user picked a duration in this run, so a value read back from
  /// the server never overwrites the choice.
  bool _durationPicked = false;
  bool _moodHintShown = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isBusy => _isBusy;
  bool get isRefreshingLive => _isRefreshingLive;
  bool get hasLiveError => _liveError;
  UserProfile? get me => _me;
  HimaSession? get myHima => _myHima;
  List<HimaSession> get friends => List.unmodifiable(_friends);
  List<FriendServer> get friendServers => List.unmodifiable(_friendServers);
  List<MatchRecord> get matches => List.unmodifiable(_matches);
  List<Knock> get inbox => List.unmodifiable(_inbox);
  List<Knock> get sent => List.unmodifiable(_sent);
  List<Guild> get guilds => List.unmodifiable(_guilds);
  List<BlockedUser> get blocks => List.unmodifiable(_blocks);
  List<RegularSlot> get regularSlots => List.unmodifiable(_regularSlots);
  List<HimaTimeSuggestion> get suggestions => List.unmodifiable(_suggestions);

  Mood get lastMood => _lastMood;
  bool get moodHintShown => _moodHintShown;

  /// The activity the next declaration would use, or the declared one.
  Activity? get selectedActivity =>
      isDeclared ? _myHima?.activity : _pendingActivity;

  int get selectedDurationMin => _durationMin;

  bool get isDeclared {
    final session = _myHima;
    return session != null && session.expiresAt.isAfter(DateTime.now().toUtc());
  }

  /// Incoming knocks already shown in the inbox. A knock stays pending until
  /// it is answered, so the badge needs its own seen state.
  final Set<String> _seenInboxIds = {};

  /// True once the reply to this knock has been displayed.
  ///
  /// `GET /app/knocks/sent` reports no per-row seen time, so the only unseen
  /// replies the app knows about are the ones the board returned into
  /// [_resultQueue]; everything else was already seen by an earlier run.
  bool isResultSeen(String knockId) =>
      !_resultQueue.any((knock) => knock.id == knockId);

  /// A pending incoming knock, a reply waiting to be shown, or an unread reply
  /// all light the header bell.
  bool get hasUnseenKnocks =>
      _inbox.any(
        (knock) =>
            knock.status == KnockStatus.pending &&
            !_seenInboxIds.contains(knock.id),
      ) ||
      _resultQueue.isNotEmpty;

  /// Called when the inbox is displayed: the dot clears without pretending the
  /// knock was answered.
  void markInboxSeen() {
    var changed = false;
    for (final knock in _inbox) {
      if (knock.status != KnockStatus.pending) continue;
      if (_seenInboxIds.add(knock.id)) changed = true;
    }
    if (changed) notifyListeners();
  }

  /// People whose knock from me is still waiting for an answer, so their さそう
  /// buttons can show 「さそった」 instead of inviting the same person twice.
  Set<String> get pendingKnockUserIds => {
    for (final knock in _sent)
      if (knock.status == KnockStatus.pending && knock.recipient != null)
        knock.recipient!.id,
  };

  /// Knocks sent before the current declaration, whose answer no longer belongs
  /// to it.
  ///
  /// The API keeps a knock and its answer forever, so without this the
  /// 「いいよ！」 pill would come back on the next poll after the user declared
  /// again.
  final Set<String> _retiredKnockIds = {};

  /// People whose knock was answered 「いいよ！」 and still belongs to the live
  /// declaration, so their card can keep the happy state instead of flipping
  /// back to さそう the moment the answer arrives.
  ///
  /// The answer is scoped to the declaration it belongs to: ending it, or
  /// letting it run out, drops the pill back to さそう. A knock has no expiry of
  /// its own in the contract, so the declaration is the boundary.
  Set<String> get acceptedKnockUserIds {
    // Read through [isDeclared] instead of a stored flag so a declaration that
    // runs out while the screen is open is covered by the same check.
    if (!isDeclared) return const {};
    return {
      for (final knock in _sent)
        if (knock.status == KnockStatus.accepted &&
            !_retiredKnockIds.contains(knock.id) &&
            knock.recipient != null)
          knock.recipient!.id,
    };
  }

  /// The plan a friend agreed to belonged to the declaration that was live when
  /// the knock was sent, so starting a new one retires every knock sent before
  /// it.
  ///
  /// Pending knocks are retired too: a knock that was still unanswered when the
  /// user declared again can be accepted afterwards by a poll, and that answer
  /// belongs to the declaration that is already over.
  void _retireSentKnocks() {
    for (final knock in _sent) {
      _retiredKnockIds.add(knock.id);
    }
  }

  /// Results already celebrated. The app shell and the knocks screen share this
  /// so a reply is celebrated exactly once, wherever the user sees it first.
  final Set<String> _celebratedResultIds = {};

  /// Returns true only the first time this result is celebrated.
  bool claimResultCelebration(String knockId) =>
      _celebratedResultIds.add(knockId);

  /// The next reply to a knock I sent that has not been celebrated yet, or null.
  ///
  /// The shell shows it as an overlay because a reply was otherwise invisible
  /// until the user opened the bell and switched to 送信. The result is claimed
  /// here so the overlay and the knocks screen never celebrate it twice.
  Knock? takeUnseenKnockResult() {
    for (final knock in _resultQueue) {
      if (_celebratedResultIds.add(knock.id)) return knock;
    }
    return null;
  }

  void markMoodHintShown() {
    if (_moodHintShown) return;
    _moodHintShown = true;
    notifyListeners();
  }

  /// Restores the token saved by a previous launch and goes straight to the main
  /// shell when `/app/me` still accepts it.
  Future<void> restoreSession() async {
    try {
      if (!await _api.restoreToken()) return;
      await _refreshAll();
      _isAuthenticated = true;
    } catch (_) {
      // A 401 has already cleared the token in the client; any other failure
      // leaves the login screen in charge, and the token stays for a retry.
    } finally {
      notifyListeners();
    }
  }

  /// The offline demo login. Only the mock answers it.
  Future<void> loginAsDemo() => _login(() => _api.loginWithDiscord(null));

  Future<void> completeDiscordLogin(DiscordAuthRequest request) =>
      _login(() => _api.loginWithDiscord(request));

  Future<void> _login(Future<void> Function() authenticate) async {
    _isBusy = true;
    notifyListeners();
    try {
      await authenticate();
      await _refreshAll();
      _isAuthenticated = true;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Reads everything the app shows. Used after login and after a mutation that
  /// changes more than one list.
  Future<void> _refreshAll() async {
    final me = await _api.getMe();
    final board = await _api.getBoard();
    final sent = await _api.getSentKnocks();
    final members = await _api.getMembers([
      for (final guild in me.guilds) guild.id,
    ]);
    final blocks = await _api.getBlocks();
    final slots = await _api.getRegularSlots();
    final forecast = await _api.getForecast();
    _applyLive(me, board, sent);
    _memberServers = members;
    // Blocks are stored before the friend list is rebuilt: the member endpoint
    // lists every visible membership, including people I blocked.
    _blocks = List.of(blocks);
    _rebuildFriendServers();
    _regularSlots = List.of(slots);
    _suggestions = List.of(forecast);
    _publishForecast(forecast);
    _liveError = false;
  }

  /// One live read: my profile and session, the board, and the knocks I sent.
  Future<void> _readLive() async {
    final me = await _api.getMe();
    final board = await _api.getBoard();
    final sent = await _api.getSentKnocks();
    _applyLive(me, board, sent);
    _rebuildFriendServers();
    _liveError = false;
  }

  void _applyLive(MeSnapshot me, BoardSnapshot board, List<Knock> sent) {
    _applyMe(me);
    _inbox = List.of(board.inbox);
    _applyResults(board.results);
    _sent = List.of(sent);
    _boardSessions = List.of(board.sessions);
    _rebuildFriends();
    _rebuildMatches();
  }

  void _applyMe(MeSnapshot me) {
    _me = me.profile;
    _guilds = List.of(me.guilds);
    final session = me.session;
    final hadSession = _myHima != null;
    if (session != null) {
      if (!hadSession && !_durationPicked) {
        // After a restart the last chosen duration is unknown. The remaining
        // time rounded up to an offered choice is the closest estimate; it is
        // taken once per session so it cannot drift while the session runs.
        _durationMin = _nearestDurationChoice(session.durationMin);
      }
      _lastMood = session.mood;
      _pendingActivity = session.activity;
    }
    _myHima = session?.withDurationMin(_durationMin);
    // This also picks up a declaration made elsewhere (the Discord bot), so the
    // worker stops suggesting while the user is already hima.
    _publishDeclaredUntil();
  }

  static int _nearestDurationChoice(int minutes) {
    for (final choice in himaDurationChoices) {
      if (choice >= minutes) return choice;
    }
    return himaDurationChoices.last;
  }

  void _applyResults(List<Knock> results) {
    if (results.isEmpty) return;
    final queuedIds = {for (final knock in _resultQueue) knock.id};
    for (final result in results) {
      // A reply that was already celebrated must not come back when the bulk
      // "seen" call has not reached the server yet.
      if (_celebratedResultIds.contains(result.id)) continue;
      if (queuedIds.add(result.id)) _resultQueue.add(result);
    }
    // One bulk call covers the whole batch, which is why the app never needs a
    // per-id "seen" request. It is repeated on the next poll if it failed.
    unawaited(
      _api.markKnockResultsSeen().catchError((Object _) {
        // Best effort: the next poll sends the same batch again.
      }),
    );
  }

  void _rebuildFriends() {
    final myId = _me?.id;
    final mine = isDeclared ? _myHima : null;
    final others = [
      for (final session in _boardSessions)
        if (session.user.id != myId) session,
    ];
    others.sort((a, b) {
      final byActivity = activityMatchRank(
        mine?.activity,
        a.activity,
      ).compareTo(activityMatchRank(mine?.activity, b.activity));
      return byActivity == 0
          ? a.user.displayName.compareTo(b.user.displayName)
          : byActivity;
    });
    _friends = others;
  }

  /// Matches are computed here from my own mood and the board rows, following
  /// the contract: only 🙂×🙂 matches; 🌙 never matches, and blocked users are
  /// already excluded by the server.
  void _rebuildMatches() {
    final mine = isDeclared ? _myHima : null;
    if (mine == null) {
      _matches = [];
      _matchCreatedAt.clear();
      return;
    }
    final now = DateTime.now().toUtc();
    final liveKeys = <String>{};
    final matches = <MatchRecord>[];
    for (final other in _friends) {
      final kind = matchKindFor(mine.mood, other.mood);
      if (kind == null) continue;
      final key = '${mine.sessionId}:${other.sessionId}';
      liveKeys.add(key);
      // Derived from the current moods, so changing the mood of a live session
      // adds or removes its match cards immediately.
      final createdAt = _matchCreatedAt.putIfAbsent(key, () => now);
      matches.add(
        MatchRecord(
          mySessionId: mine.sessionId,
          otherSessionId: other.sessionId,
          kind: kind,
          otherUser: other.user,
          otherHima: MatchedHima(
            mood: other.mood,
            activity: other.activity,
            note: other.note,
            expiresAt: other.expiresAt,
          ),
          createdAt: createdAt,
        ),
      );
    }
    _matchCreatedAt.removeWhere((key, _) => !liveKeys.contains(key));
    matches.sort((a, b) {
      final byActivity = activityMatchRank(
        mine.activity,
        a.otherHima.activity,
      ).compareTo(activityMatchRank(mine.activity, b.otherHima.activity));
      return byActivity == 0
          ? b.createdAt.compareTo(a.createdAt)
          : byActivity;
    });
    _matches = matches;
  }

  void _rebuildFriendServers() {
    final myId = _me?.id;
    final himaByUserId = {
      for (final session in _boardSessions)
        if (session.user.id != myId) session.user.id: session,
    };
    final blockedIds = {for (final block in _blocks) block.user.id};
    // The member endpoint is a flat list of every visible membership, so the
    // grouping happens here: the server name and its visibility only exist in my
    // `/app/me` memberships. A member of a server missing from those memberships
    // has no name to show under, so it is dropped.
    final membersByGuild = <String, List<UserSummary>>{};
    for (final member in _memberServers) {
      // The list includes me when my own membership is visible, and it includes
      // people I blocked; neither belongs in the 友達 tab.
      if (member.user.id == myId || blockedIds.contains(member.user.id)) {
        continue;
      }
      (membersByGuild[member.guildId] ??= []).add(member.user);
    }
    final servers = <FriendServer>[];
    for (final guild in _guilds) {
      final members = membersByGuild[guild.id];
      if (members == null || members.isEmpty) continue;
      servers.add(
        FriendServer(
          guild: guild,
          members: _sortedMembers([
            for (final member in members)
              FriendMember(
                user: member,
                // A hidden server still lists its members, but not what they
                // are doing right now.
                hima: guild.visible ? himaByUserId[member.id] : null,
              ),
          ]),
        ),
      );
    }
    _friendServers = servers;
  }

  static List<FriendMember> _sortedMembers(List<FriendMember> members) =>
      members..sort((a, b) {
        if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
        return a.user.displayName.compareTo(b.user.displayName);
      });

  /// Reads the data the home screen shows live.
  ///
  /// A poll can be in flight while the user declares, ends or edits hima. The
  /// generation guard keeps such a stale read from overwriting the state the
  /// successful mutation just produced; the discarded pass is repeated so the
  /// screen still converges to the server state. A read that outlives the
  /// session is dropped and never retried.
  Future<void> refreshLiveData() async {
    if (!_isAuthenticated) return;
    if (_isRefreshingLive) {
      // The running poll may have started before the mutation, so queue a pass
      // that reads the committed state instead of dropping this request.
      _refreshQueued = true;
      return;
    }
    _isRefreshingLive = true;
    try {
      do {
        _refreshQueued = false;
        final generation = _stateGeneration;
        try {
          final me = await _api.getMe();
          final board = await _api.getBoard();
          final sent = await _api.getSentKnocks();
          if (generation != _stateGeneration || !_isAuthenticated) {
            // A mutation committed while this read was in flight, or the session
            // ended: these results are older than the state held here, so drop
            // them. Only a still signed-in model is worth reading again.
            _refreshQueued = _isAuthenticated;
            continue;
          }
          _applyLive(me, board, sent);
          _rebuildFriendServers();
          _liveError = false;
        } catch (_) {
          // Keep the last good data and let the UI offer a retry instead of
          // pretending the refresh succeeded.
          _liveError = true;
        }
      } while (_refreshQueued);
    } finally {
      _isRefreshingLive = false;
      notifyListeners();
    }
  }

  /// Records that the state held here is newer than any read already in flight.
  void _invalidateLiveReads() {
    _stateGeneration++;
  }

  /// Mirrors the live declaration to the native worker, so it stops suggesting
  /// while the user is already hima.
  ///
  /// [expiresAt] is the expiry a declaration or an extend just returned;
  /// without it the local session decides.
  void _publishDeclaredUntil({DateTime? expiresAt}) {
    final until = expiresAt ?? _myHima?.expiresAt;
    // An expired session has to read as "not declared", or the worker would
    // stay silent after the user is free again.
    final live = until != null && until.isAfter(DateTime.now().toUtc());
    _ignoreBridgeErrors(_bridge.setDeclaredUntil(live ? until : null));
  }

  void _publishForecast(List<HimaTimeSuggestion> forecast) =>
      _ignoreBridgeErrors(_bridge.setForecast(forecast));

  /// The worker is a convenience: a failed mirror must not surface as an error
  /// in a flow that already succeeded on the server.
  static void _ignoreBridgeErrors(Future<void> call) {
    unawaited(call.catchError((Object _) {}));
  }

  /// Re-reads the forecast and hands it to the worker, which suggests around the
  /// times the user is usually free.
  ///
  /// Runs when the app comes back to the foreground and after a regular slot
  /// changes, so a deleted slot stops being suggested.
  Future<void> refreshSuggestForecast() async {
    // Nothing to mirror where the worker does not exist, and the request would
    // be paid on every resume.
    if (!_bridge.isSupported) return;
    try {
      final forecast = await _api.getForecast();
      _suggestions = List.of(forecast);
      _publishForecast(forecast);
    } catch (_) {
      // Best effort: the worker keeps the slots it already has.
    }
  }

  void startPolling() {
    if (!_isAuthenticated || _pollTimer != null) return;
    // Push is not configured yet, so foreground updates use the shared API.
    unawaited(refreshLiveData());
    // Coming back to the foreground is when the times the worker suggests from
    // are most likely to be stale.
    unawaited(refreshSuggestForecast());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refreshLiveData()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Re-reads the state after a committed mutation.
  ///
  /// The mutation already succeeded, so a failing read must not be reported as
  /// a failed mutation; it raises [hasLiveError] instead, which the screen shows
  /// with a retry.
  Future<void> _refreshAfterMutation() async {
    try {
      await _readLive();
    } catch (_) {
      _liveError = true;
    }
    notifyListeners();
  }

  /// Declares hima. Passing no mood keeps the last used one so the hero button
  /// stays a true one-tap action.
  ///
  /// [source] records where the declaration came from: the home actions leave it
  /// [DeclarationSource.manual], and the notification suggestion passes
  /// [DeclarationSource.suggested].
  Future<void> declareHima({
    Mood? mood,
    Activity? activity,
    int? durationMin,
    String? note,
    DeclarationSource source = DeclarationSource.manual,
  }) async {
    final minutes = durationMin ?? _durationMin;
    final expiresAt = await _api.declareHima(
      HimaDeclaration(
        mood: mood ?? _lastMood,
        activity: activity ?? _pendingActivity,
        note: note,
        durationMin: minutes,
        source: source,
      ),
    );
    _durationMin = minutes;
    _durationPicked = true;
    _invalidateLiveReads();
    _retireSentKnocks();
    // The response carries the new expiry, so the native side is correct even
    // if the follow-up /app/me read fails.
    _publishDeclaredUntil(expiresAt: expiresAt);
    await _refreshAfterMutation();
  }

  /// Changes only the mood. The server extends the live session, so this is the
  /// same POST as a declaration.
  Future<void> changeMood(Mood mood) async {
    final current = isDeclared ? _myHima : null;
    if (current == null) {
      _lastMood = mood;
      notifyListeners();
      return;
    }
    await _declareLike(current, mood: mood, activity: current.activity);
  }

  /// Chips only remember the choice until the user declares hima. An expired
  /// session must not be revived by a chip tap, so the guard is [isDeclared].
  Future<void> selectActivity(Activity? activity) async {
    final current = isDeclared ? _myHima : null;
    if (current == null) {
      _pendingActivity = activity;
      notifyListeners();
      return;
    }
    _pendingActivity = activity;
    await _declareLike(current, activity: activity);
  }

  Future<void> selectDuration(int minutes) async {
    final current = isDeclared ? _myHima : null;
    _durationMin = minutes;
    _durationPicked = true;
    if (current == null) {
      notifyListeners();
      return;
    }
    await _declareLike(
      current,
      activity: current.activity,
      durationMin: minutes,
    );
  }

  /// Re-declares with one field changed; the server extends the live session.
  ///
  /// [activity] is required rather than optional so "keep the current activity"
  /// and "the user chose no activity" (null, sent as `any`) stay distinct.
  Future<void> _declareLike(
    HimaSession current, {
    Mood? mood,
    required Activity? activity,
    int? durationMin,
  }) async {
    final expiresAt = await _api.declareHima(
      HimaDeclaration(
        mood: mood ?? current.mood,
        activity: activity,
        note: current.note,
        durationMin: durationMin ?? _durationMin,
        source: current.source ?? DeclarationSource.manual,
      ),
    );
    _invalidateLiveReads();
    // An extend moves the expiry as well, and the worker would go quiet too
    // early with the old one.
    _publishDeclaredUntil(expiresAt: expiresAt);
    await _refreshAfterMutation();
  }

  Future<void> endHima() async {
    await _api.endHima();
    _invalidateLiveReads();
    _myHima = null;
    // Nothing is declared any more, so the worker may suggest again.
    _publishDeclaredUntil();
    notifyListeners();
    await _refreshAfterMutation();
  }

  Future<Knock> sendKnock(String userId, KnockTemplate template) async {
    final to = _knownUser(userId) ?? UserSummary(id: userId, displayName: '');
    // The knock is committed by this call. A failing follow-up read must not be
    // reported as a failed send, or a retry would send a duplicate.
    final knock = await _api.createKnock(to: to, template: template);
    _invalidateLiveReads();
    // Kept locally so 「さそった」 shows at once, before the next read of
    // `GET /app/knocks/sent` returns.
    if (!_sent.any((item) => item.id == knock.id)) _sent.insert(0, knock);
    notifyListeners();
    await _refreshKnocksQuietly();
    // Mock replies arrive after three seconds; a short refresh makes them
    // visible without waiting for the 30 second poll.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4), _refreshKnocksQuietly),
    );
    return knock;
  }

  /// Best-effort read used after a committed mutation: the foreground poll
  /// retries, and the mutation itself is already reported as successful.
  Future<void> _refreshKnocksQuietly() async {
    try {
      final board = await _api.getBoard();
      final sent = await _api.getSentKnocks();
      _inbox = List.of(board.inbox);
      _applyResults(board.results);
      _sent = List.of(sent);
      notifyListeners();
    } catch (_) {
      // Keep the committed state instead of surfacing a false failure.
    }
  }

  Future<void> respondToKnock(String knockId, KnockStatus response) async {
    await _api.respondToKnock(knockId, response);
    _invalidateLiveReads();
    await _refreshKnocksQuietly();
  }

  /// Marks a reply as seen locally.
  ///
  /// The server marks results in bulk as soon as the board returns them, and
  /// `GET /app/knocks/sent` reports no per-row seen time, so dropping the reply
  /// from the queue is what clears its 「新着」 state and the header badge.
  Future<void> markKnockResultSeen(String knockId) async {
    _resultQueue.removeWhere((knock) => knock.id == knockId);
    notifyListeners();
  }

  Future<void> updateSettings({bool? autoMode, Mood? autoMood}) async {
    final profile = _me;
    if (profile == null) return;
    final updated = await _api.updateSettings(
      autoMode: autoMode,
      autoMood: autoMood,
    );
    _invalidateLiveReads();
    _me = profile.withSettings(updated);
    notifyListeners();
  }

  Future<void> updateGuildVisibility(String guildId, bool visible) async {
    final stored = await _api.updateGuildVisibility(guildId, visible);
    _invalidateLiveReads();
    _guilds = [
      for (final guild in _guilds)
        guild.id == guildId ? guild.withVisibility(stored) : guild,
    ];
    notifyListeners();
    // What I can see depends on which servers are visible, so the board is read
    // again rather than patched.
    await _refreshAfterMutation();
  }

  Future<void> addBlock(String userId) async {
    await _api.createBlock(userId);
    _invalidateLiveReads();
    await _reloadBlocks();
    await _refreshAfterMutation();
  }

  Future<void> removeBlock(String userId) async {
    await _api.deleteBlock(userId);
    _invalidateLiveReads();
    await _reloadBlocks();
    await _refreshAfterMutation();
  }

  Future<void> _reloadBlocks() async {
    // A block also hides the person from the 友達 tab, so the friend list is
    // rebuilt from the list just read.
    _blocks = List.of(await _api.getBlocks());
    _rebuildFriendServers();
  }

  /// Looks a person up in what the app already knows, for the places where the
  /// server only gives an id.
  UserSummary? _knownUser(String id) {
    for (final friend in _friends) {
      if (friend.user.id == id) return friend.user;
    }
    for (final server in _friendServers) {
      for (final member in server.members) {
        if (member.user.id == id) return member.user;
      }
    }
    for (final knock in _inbox) {
      final sender = knock.sender;
      if (sender != null && sender.id == id) return sender;
    }
    for (final knock in _sent) {
      final recipient = knock.recipient;
      if (recipient != null && recipient.id == id) return recipient;
    }
    return null;
  }

  Future<void> addRegularSlot(RegularSlot slot) async {
    final saved = await _api.addRegularSlot(slot);
    _invalidateLiveReads();
    _regularSlots = [..._regularSlots, saved]..sort(_compareSlots);
    notifyListeners();
    await refreshSuggestForecast();
  }

  Future<void> deleteRegularSlot(RegularSlot slot) async {
    final id = slot.id;
    if (id == null) return;
    await _api.deleteRegularSlot(id);
    _invalidateLiveReads();
    _regularSlots = [
      for (final item in _regularSlots)
        if (item.id != id) item,
    ];
    notifyListeners();
    // The forecast is built from these slots, so a removed time must be pushed
    // again or the worker keeps suggesting it.
    await refreshSuggestForecast();
  }

  static int _compareSlots(RegularSlot a, RegularSlot b) {
    final byDay = a.weekday.compareTo(b.weekday);
    return byDay == 0 ? a.startMin.compareTo(b.startMin) : byDay;
  }

  /// Drops the local session when the server rejects the token. The client has
  /// already cleared the stored token by the time this runs.
  void _handleUnauthorized() {
    stopPolling();
    _invalidateLiveReads();
    _resetSession();
    notifyListeners();
  }

  Future<void> logout() async {
    stopPolling();
    // A live refresh still in flight belongs to the session being ended: drop
    // its results instead of letting it repopulate the signed-out model.
    _invalidateLiveReads();
    await _api.logout();
    _resetSession();
    notifyListeners();
  }

  void _resetSession() {
    _isAuthenticated = false;
    _me = null;
    _myHima = null;
    _boardSessions = [];
    _friends = [];
    _friendServers = [];
    _memberServers = [];
    _matches = [];
    _matchCreatedAt.clear();
    _inbox = [];
    _sent = [];
    _resultQueue.clear();
    _seenInboxIds.clear();
    _celebratedResultIds.clear();
    _retiredKnockIds.clear();
    _guilds = [];
    _blocks = [];
    _regularSlots = [];
    _suggestions = [];
    _pendingActivity = null;
    _durationMin = defaultHimaDurationMin;
    _durationPicked = false;
    _lastMood = Mood.ok;
    _moodHintShown = false;
    _liveError = false;
    // The worker keeps this user's targets, forecast and declaration, so it is
    // wiped whenever the app goes back to the login screen.
    _ignoreBridgeErrors(_bridge.clear());
  }
}
