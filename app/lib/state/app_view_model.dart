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
  UserProfile? _me;
  HimaSession? _myHima;
  List<HimaSession> _friends = [];
  List<MatchRecord> _matches = [];
  List<Knock> _inbox = [];
  List<Knock> _sent = [];
  List<Guild> _guilds = [];
  List<BlockedUser> _blocks = [];
  List<RegularSlot> _regularSlots = [];
  List<HimaTimeSuggestion> _suggestions = [];

  bool get isAuthenticated => _isAuthenticated;
  bool get isBusy => _isBusy;
  UserProfile? get me => _me;
  HimaSession? get myHima => _myHima;
  List<HimaSession> get friends => List.unmodifiable(_friends);
  List<MatchRecord> get matches => List.unmodifiable(_matches);
  List<Knock> get inbox => List.unmodifiable(_inbox);
  List<Knock> get sent => List.unmodifiable(_sent);
  List<Guild> get guilds => List.unmodifiable(_guilds);
  List<BlockedUser> get blocks => List.unmodifiable(_blocks);
  List<RegularSlot> get regularSlots => List.unmodifiable(_regularSlots);
  List<HimaTimeSuggestion> get suggestions => List.unmodifiable(_suggestions);

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
    _matches = results[4] as List<MatchRecord>;
    _inbox = results[5] as List<Knock>;
    _sent = results[6] as List<Knock>;
    _blocks = results[7] as List<BlockedUser>;
    _regularSlots = results[8] as List<RegularSlot>;
    _suggestions = results[9] as List<HimaTimeSuggestion>;
  }

  Future<void> refreshLiveData() async {
    if (!_isAuthenticated || _isRefreshingLive) return;
    _isRefreshingLive = true;
    try {
      final results = await Future.wait<Object?>([
        _api.getHima(),
        _api.getMyHima(),
        _api.getMatches(),
        _api.getKnockInbox(),
        _api.getKnockSent(),
      ]);
      _friends = results[0] as List<HimaSession>;
      _myHima = results[1] as HimaSession?;
      _matches = results[2] as List<MatchRecord>;
      _inbox = results[3] as List<Knock>;
      _sent = results[4] as List<Knock>;
      notifyListeners();
    } finally {
      _isRefreshingLive = false;
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

  Future<HimaSession> declareHima(HimaDeclaration declaration) async {
    final session = await _api.putMyHima(declaration);
    await refreshLiveData();
    return session;
  }

  Future<void> endHima() async {
    await _api.deleteMyHima();
    await refreshLiveData();
  }

  Future<Knock> sendKnock(String userId, KnockTemplate template) async {
    final knock = await _api.createKnock(userId: userId, template: template);
    await refreshKnocks();
    // Mock replies arrive after three seconds; a short refresh makes them visible.
    unawaited(Future<void>.delayed(const Duration(seconds: 4), refreshKnocks));
    return knock;
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
    await refreshKnocks();
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
    _matches = [];
    _inbox = [];
    _sent = [];
    _guilds = [];
    _blocks = [];
    _regularSlots = [];
    _suggestions = [];
    notifyListeners();
  }
}
