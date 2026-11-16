import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/models/models.dart';

class AppViewModel extends ChangeNotifier {
  AppViewModel(this._api);

  final ApiClient _api;
  Timer? _pollTimer;
  bool _isAuthenticated = false;
  bool _isBusy = false;
  bool _isRefreshingLive = false;
  bool _liveError = false;
  UserProfile? _me;
  HimaSession? _myHima;
  List<HimaSession> _friends = [];
  List<FriendServer> _friendServers = [];
  List<MatchRecord> _matches = [];
  List<Knock> _inbox = [];
  List<Knock> _sent = [];
  List<Guild> _guilds = [];
  List<BlockedUser> _blocks = [];
  List<RegularSlot> _regularSlots = [];
  List<HimaTimeSuggestion> _suggestions = [];

  // Remembered between declarations so a single tap can declare again without
  // asking a question. `auto_mood` in settings is unrelated (it belongs to the
  // server-side auto mode) and must not be reused here.
  Mood _lastMood = Mood.ok;
  Activity? _pendingActivity;
  int _durationMin = defaultHimaDurationMin;
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

  int get selectedDurationMin =>
      isDeclared ? _myHima!.durationMin : _durationMin;

  bool get isDeclared {
    final session = _myHima;
    return session != null && session.expiresAt.isAfter(DateTime.now().toUtc());
  }

  /// Incoming knocks already shown in the inbox. A knock stays pending until
  /// it is answered, so the badge needs its own seen state.
  final Set<String> _seenInboxIds = {};

  /// A pending incoming knock or an unread reply both light the header bell.
  bool get hasUnseenKnocks =>
      _inbox.any(
        (knock) =>
            knock.status == KnockStatus.pending &&
            !_seenInboxIds.contains(knock.id),
      ) ||
      _sent.any(
        (knock) =>
            knock.status != KnockStatus.pending && knock.resultSeenAt == null,
      );

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

  /// Accepted results already celebrated. Home and the knocks screen share this
  /// so a reply is celebrated exactly once, wherever the user sees it first.
  final Set<String> _celebratedResultIds = {};

  /// Returns true only the first time this result is celebrated.
  bool claimResultCelebration(String knockId) =>
      _celebratedResultIds.add(knockId);

  void markMoodHintShown() {
    if (_moodHintShown) return;
    _moodHintShown = true;
    notifyListeners();
  }

  Future<void> loginAsDemo() async {
    _isBusy = true;
    notifyListeners();
    try {
      _me = await _api.loginWithDiscord(null);
      _isAuthenticated = true;
      await _refreshAll();
    } catch (_) {
      _isAuthenticated = false;
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> completeDiscordLogin(DiscordAuthRequest request) async {
    _isBusy = true;
    notifyListeners();
    try {
      _me = await _api.loginWithDiscord(request);
      _isAuthenticated = true;
      await _refreshAll();
    } catch (_) {
      _isAuthenticated = false;
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _refreshAll() async {
    final results = await Future.wait<Object?>([
      _api.getMe(),
      _api.getGuilds(),
      _api.getMyHima(),
      _api.getHima(),
      _api.getFriends(),
      _api.getMatches(),
      _api.getKnockInbox(),
      _api.getKnockSent(),
      _api.getBlocks(),
      _api.getRegularSlots(),
      _api.getHimaTimeSuggestions(),
    ]);
    _me = results[0] as UserProfile;
    _guilds = results[1] as List<Guild>;
    _myHima = results[2] as HimaSession?;
    _friends = results[3] as List<HimaSession>;
    _friendServers = results[4] as List<FriendServer>;
    _matches = results[5] as List<MatchRecord>;
    _inbox = results[6] as List<Knock>;
    _sent = results[7] as List<Knock>;
    _blocks = results[8] as List<BlockedUser>;
    _regularSlots = results[9] as List<RegularSlot>;
    _suggestions = results[10] as List<HimaTimeSuggestion>;
    _liveError = false;
  }

  Future<void> refreshLiveData() async {
    if (!_isAuthenticated || _isRefreshingLive) return;
    _isRefreshingLive = true;
    try {
      final results = await Future.wait<Object?>([
        _api.getHima(),
        _api.getMyHima(),
        _api.getFriends(),
        _api.getMatches(),
        _api.getKnockInbox(),
        _api.getKnockSent(),
      ]);
      _friends = results[0] as List<HimaSession>;
      _myHima = results[1] as HimaSession?;
      _friendServers = results[2] as List<FriendServer>;
      _matches = results[3] as List<MatchRecord>;
      _inbox = results[4] as List<Knock>;
      _sent = results[5] as List<Knock>;
      _liveError = false;
    } catch (_) {
      // Keep the last good data and let the UI offer a retry instead of
      // pretending the refresh succeeded.
      _liveError = true;
    } finally {
      _isRefreshingLive = false;
      notifyListeners();
    }
  }

  void startPolling() {
    if (!_isAuthenticated || _pollTimer != null) return;
    // Push is not configured yet, so foreground updates use the shared API.
    unawaited(refreshLiveData());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refreshLiveData()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Declares hima. Passing no mood keeps the last used one so the hero button
  /// stays a true one-tap action.
  Future<HimaSession> declareHima({
    Mood? mood,
    Activity? activity,
    int? durationMin,
    String? note,
  }) async {
    final session = await _api.putMyHima(
      HimaDeclaration(
        mood: mood ?? _lastMood,
        activity: activity ?? _pendingActivity,
        note: note,
        durationMin: durationMin ?? _durationMin,
        source: DeclarationSource.manual,
      ),
    );
    _applySession(session);
    await refreshLiveData();
    return session;
  }

  /// Changes only the mood. The API keeps the session id for a live session.
  Future<void> changeMood(Mood mood) async {
    final current = isDeclared ? _myHima : null;
    if (current == null) {
      _lastMood = mood;
      notifyListeners();
      return;
    }
    final session = await _api.putMyHima(
      HimaDeclaration(
        mood: mood,
        activity: current.activity,
        note: current.note,
        durationMin: current.durationMin,
        source: current.source ?? DeclarationSource.manual,
      ),
    );
    _applySession(session);
    await refreshLiveData();
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
    final session = await _api.putMyHima(
      HimaDeclaration(
        mood: current.mood,
        activity: activity,
        note: current.note,
        durationMin: current.durationMin,
        source: current.source ?? DeclarationSource.manual,
      ),
    );
    _applySession(session);
    await refreshLiveData();
  }

  Future<void> selectDuration(int minutes) async {
    final current = isDeclared ? _myHima : null;
    if (current == null) {
      _durationMin = minutes;
      notifyListeners();
      return;
    }
    final session = await _api.putMyHima(
      HimaDeclaration(
        mood: current.mood,
        activity: current.activity,
        note: current.note,
        durationMin: minutes,
        source: current.source ?? DeclarationSource.manual,
      ),
    );
    _applySession(session);
    await refreshLiveData();
  }

  void _applySession(HimaSession session) {
    _myHima = session;
    _lastMood = session.mood;
    _pendingActivity = session.activity;
    _durationMin = session.durationMin;
    notifyListeners();
  }

  Future<void> endHima() async {
    await _api.deleteMyHima();
    _myHima = null;
    notifyListeners();
    await refreshLiveData();
  }

  Future<Knock> sendKnock(String userId, KnockTemplate template) async {
    // The knock is committed by this call. A failing follow-up read must not be
    // reported as a failed send, or a retry would send a duplicate.
    final knock = await _api.createKnock(userId: userId, template: template);
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
      await refreshKnocks();
    } catch (_) {
      // Keep the committed state instead of surfacing a false failure.
    }
  }

  Future<void> refreshKnocks() async {
    final results = await Future.wait<Object?>([
      _api.getKnockInbox(),
      _api.getKnockSent(),
    ]);
    _inbox = results[0] as List<Knock>;
    _sent = results[1] as List<Knock>;
    notifyListeners();
  }

  Future<void> respondToKnock(String knockId, KnockStatus response) async {
    await _api.respondToKnock(knockId, response);
    await _refreshKnocksQuietly();
  }

  Future<void> markKnockResultSeen(String knockId) async {
    final seenAt =
        await _api.markKnockResultSeen(knockId) ?? DateTime.now().toUtc();
    _sent = _sent.map((knock) {
      if (knock.id != knockId) return knock;
      return Knock(
        id: knock.id,
        sender: knock.sender,
        recipient: knock.recipient,
        template: knock.template,
        status: knock.status,
        createdAt: knock.createdAt,
        guild: knock.guild,
        message: knock.message,
        respondedAt: knock.respondedAt,
        recipientNote: knock.recipientNote,
        resultSeenAt: seenAt,
      );
    }).toList();
    notifyListeners();
  }

  Future<void> updateSettings({
    bool? autoMode,
    Mood? autoMood,
    bool? notifyOnHima,
  }) async {
    final current = _me?.settings;
    final profile = _me;
    if (current == null || profile == null) return;
    final updated = await _api.updateSettings(
      UserSettings(
        autoMode: autoMode ?? current.autoMode,
        autoMood: autoMood ?? current.autoMood,
        notifyOnHima: notifyOnHima ?? current.notifyOnHima,
      ),
    );
    _me = UserProfile(
      id: profile.id,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
      settings: updated,
    );
    notifyListeners();
  }

  Future<void> updateGuildVisibility(String guildId, bool visible) async {
    final updated = await _api.updateGuildVisibility(guildId, visible);
    _guilds = _guilds
        .map((guild) => guild.id == guildId ? updated : guild)
        .toList();
    await refreshLiveData();
  }

  Future<void> addBlock(String userId) async {
    await _api.createBlock(userId);
    _blocks = await _api.getBlocks();
    await refreshLiveData();
  }

  Future<void> removeBlock(String userId) async {
    await _api.deleteBlock(userId);
    _blocks = await _api.getBlocks();
    await refreshLiveData();
  }

  Future<void> saveRegularSlots(List<RegularSlot> slots) async {
    _regularSlots = await _api.putRegularSlots(slots);
    notifyListeners();
  }

  Future<void> logout() async {
    stopPolling();
    await _api.logout();
    _isAuthenticated = false;
    _me = null;
    _myHima = null;
    _friends = [];
    _friendServers = [];
    _matches = [];
    _inbox = [];
    _sent = [];
    _seenInboxIds.clear();
    _celebratedResultIds.clear();
    _guilds = [];
    _blocks = [];
    _regularSlots = [];
    _suggestions = [];
    _pendingActivity = null;
    _durationMin = defaultHimaDurationMin;
    _lastMood = Mood.ok;
    _moodHintShown = false;
    notifyListeners();
  }
}
