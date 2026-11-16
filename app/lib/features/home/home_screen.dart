import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_spacing.dart';
import '../../data/models/models.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/shake.dart';
import '../../state/app_view_model.dart';
import '../knocks/knocks_screen.dart';
import '../knocks/widgets/knock_sheet.dart';
import '../profile/settings_screen.dart';
import 'hero_state.dart';
import 'widgets/friends_section.dart';
import 'widgets/home_header.dart';
import 'widgets/match_card.dart';
import 'widgets/my_status_hero.dart';
import 'widgets/pickers.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  int _burstToken = 0;
  int _shakeToken = 0;

  // One key per control that can fail to save, so a failure shakes the control
  // the user touched instead of the whole hero.
  final GlobalKey<ShakeState> _moodShakeKey = GlobalKey<ShakeState>();
  final GlobalKey<ShakeState> _durationShakeKey = GlobalKey<ShakeState>();
  final GlobalKey<ShakeState> _activityShakeKey = GlobalKey<ShakeState>();

  bool _justExpired = false;
  Timer? _expiredTimer;
  bool _hintVisible = false;
  Timer? _hintTimer;

  final Set<String> _seenMatchIds = {};
  bool _primed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewModel = context.read<AppViewModel>();
      if (viewModel.moodHintShown) return;
      // Marked as shown immediately so switching tabs does not bring it back;
      // the local timer only decides how long it stays on screen.
      viewModel.markMoodHintShown();
      setState(() => _hintVisible = true);
      _hintTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _hintVisible = false);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchMatches(context.read<AppViewModel>().matches);
    _primed = true;
  }

  @override
  void dispose() {
    _expiredTimer?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  /// The first frame only records what already exists so opening the app does
  /// not replay haptics for old matches.
  void _watchMatches(List<MatchRecord> matches) {
    final fresh = matches
        .map((match) => match.id)
        .where(_seenMatchIds.add)
        .toList();
    if (!_primed || fresh.isEmpty) return;
    AppHaptics.match();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _declare(Mood mood) async {
    if (_busy) return;
    final viewModel = context.read<AppViewModel>();
    setState(() => _busy = true);
    try {
      await viewModel.declareHima(mood: mood);
      if (!mounted) return;
      setState(() {
        _burstToken++;
        _justExpired = false;
      });
      AppHaptics.declare();
    } catch (_) {
      if (!mounted) return;
      AppHaptics.error();
      setState(() => _shakeToken++);
      _showMessage('宣言できなかった。もう一度試してね');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    final viewModel = context.read<AppViewModel>();
    try {
      await viewModel.endHima();
      if (!mounted) return;
      AppHaptics.end();
      setState(() => _justExpired = false);
    } catch (_) {
      if (!mounted) return;
      AppHaptics.error();
      _showMessage('終了できなかった。もう一度試してね');
    }
  }

  Future<void> _changeMood() async {
    final viewModel = context.read<AppViewModel>();
    final current = viewModel.myHima;
    if (current == null) return;
    final mood = await showMoodPicker(context, current: current.mood);
    if (mood == null || mood == current.mood || !mounted) return;
    try {
      await viewModel.changeMood(mood);
      if (!mounted) return;
      AppHaptics.select();
    } catch (_) {
      if (!mounted) return;
      AppHaptics.error();
      _moodShakeKey.currentState?.shake();
      _showMessage('変更できなかった。もう一度試してね');
    }
  }

  Future<void> _changeDuration() async {
    final viewModel = context.read<AppViewModel>();
    final current = viewModel.myHima;
    if (current == null) return;
    final minutes = await showDurationPicker(
      context,
      current: current.durationMin,
    );
    if (minutes == null || minutes == current.durationMin || !mounted) return;
    try {
      await viewModel.selectDuration(minutes);
      if (!mounted) return;
      AppHaptics.select();
    } catch (_) {
      if (!mounted) return;
      AppHaptics.error();
      _durationShakeKey.currentState?.shake();
      _showMessage('変更できなかった。もう一度試してね');
    }
  }

  Future<void> _selectActivity(Activity? activity) async {
    final viewModel = context.read<AppViewModel>();
    try {
      await viewModel.selectActivity(activity);
    } catch (_) {
      if (!mounted) return;
      AppHaptics.error();
      _activityShakeKey.currentState?.shake();
      _showMessage('変更できなかった。もう一度試してね');
    }
  }

  void _handleExpired() {
    if (!mounted) return;
    setState(() => _justExpired = true);
    _expiredTimer?.cancel();
    _expiredTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _justExpired = false);
    });
    // The declaration must end on the shared side too, not only on screen.
    unawaited(context.read<AppViewModel>().refreshLiveData());
  }

  void _openKnocks() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const KnocksScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _knock(
    UserSummary user, {
    Activity? activity,
    Mood? mood,
  }) => showKnockSheet(context, user: user, activity: activity, mood: mood);

  /// One card per match kind, in a fixed order.
  ///
  /// A card per person flooded the screen (four cards with 🔥) and repeated the
  /// people the friend grid already lists, so the friends of a kind share one
  /// card.
  List<MatchCard> _matchCards(
    List<MatchRecord> matches,
    Set<String> pendingUserIds,
  ) {
    const order = [MatchKind.fireFire, MatchKind.fireOk, MatchKind.okOk];
    return [
      for (final kind in order)
        if (matches.any((match) => match.kind == kind))
          MatchCard(
            key: ValueKey(kind),
            kind: kind,
            matches: matches.where((match) => match.kind == kind).toList(),
            pendingUserIds: pendingUserIds,
            onKnock: (match) => _knock(
              match.otherUser,
              activity: match.otherHima.activity,
              mood: match.otherHima.mood,
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final me = viewModel.me;
    final state = HeroState.fromSession(
      viewModel.myHima,
      justExpired: _justExpired,
      fallbackMood: viewModel.lastMood,
    );
    final pendingUserIds = viewModel.pendingKnockUserIds;
    final matchCards = _matchCards(viewModel.matches, pendingUserIds);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      children: [
        HomeHeader(
          hasKnockBadge: viewModel.hasUnseenKnocks,
          onOpenKnocks: _openKnocks,
          onOpenSettings: _openSettings,
        ),
        const SizedBox(height: AppSpacing.s16),
        if (me != null)
          MyStatusHero(
            state: state,
            me: me,
            lastMood: viewModel.lastMood,
            selectedActivity: viewModel.selectedActivity,
            busy: _busy,
            burstToken: _burstToken,
            shakeToken: _shakeToken,
            moodShakeKey: _moodShakeKey,
            durationShakeKey: _durationShakeKey,
            activityShakeKey: _activityShakeKey,
            showHint: _hintVisible,
            onDeclare: _declare,
            onEnd: _end,
            onChangeMood: _changeMood,
            onChangeDuration: _changeDuration,
            onSelectActivity: _selectActivity,
            onExpired: _handleExpired,
          ),
        if (matchCards.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          for (final card in matchCards)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: card,
            ),
        ],
        const SizedBox(height: AppSpacing.s24),
        FriendsSection(
          friends: viewModel.friends,
          pendingUserIds: pendingUserIds,
          loading: viewModel.isRefreshingLive,
          hasError: viewModel.hasLiveError,
          onRetry: () => unawaited(viewModel.refreshLiveData()),
          onKnock: (friend) => _knock(
            friend.user,
            activity: friend.activity,
            mood: friend.mood,
          ),
        ),
      ],
    );
  }
}
