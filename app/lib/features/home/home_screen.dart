import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_spacing.dart';
import '../../data/models/models.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/app_bottom_navigation.dart';
import '../../shared/widgets/paint/paint_thick.dart';
import '../../shared/widgets/shake.dart';
import '../../state/app_view_model.dart';
import '../../state/session_owner.dart';
import '../knocks/knocks_screen.dart';
import '../knocks/widgets/knock_sheet.dart';
import '../profile/settings_screen.dart';
import 'declare_feedback.dart';
import 'hero_picks.dart';
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
  final GlobalKey<MyStatusHeroState> _heroKey = GlobalKey<MyStatusHeroState>();
  DemoSession? _demoSession;

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
    final demo = context.read<DemoSession?>();
    if (!identical(demo, _demoSession)) {
      _demoSession?.homePickerRequest.removeListener(_handleDemoPickerRequest);
      _demoSession = demo;
      _demoSession?.homePickerRequest.addListener(_handleDemoPickerRequest);
      if (demo != null) {
        // A demo panel can queue the request before switching tabs, while this
        // screen is unmounted. Read it after the hero has joined the tree.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleDemoPickerRequest();
        });
      }
    }
    _watchMatches(context.read<AppViewModel>().matches);
    _primed = true;
  }

  @override
  void dispose() {
    _demoSession?.homePickerRequest.removeListener(_handleDemoPickerRequest);
    _expiredTimer?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  void _handleDemoPickerRequest() {
    final demo = _demoSession;
    final request = demo?.homePickerRequest.value;
    if (demo == null || request == null) return;
    final opened = _heroKey.currentState?.openInlinePicker(
      request.kind == DemoHomePickerKind.activity
          ? HeroInlinePicker.activity
          : HeroInlinePicker.duration,
    );
    if (opened ?? false) demo.homePickerRequest.value = null;
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
      setState(() => _shakeToken++);
      showDeclareFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ends the declaration and reports whether the server accepted it.
  ///
  /// The hero needs the answer: it wipes the declared paint off, and on a
  /// failure it puts the paint back instead of leaving the paper state on screen
  /// and then flipping back to the declared one.
  Future<bool> _end() async {
    final viewModel = context.read<AppViewModel>();
    try {
      await viewModel.endHima();
      if (!mounted) return true;
      AppHaptics.end();
      setState(() => _justExpired = false);
      return true;
    } catch (_) {
      if (!mounted) return false;
      AppHaptics.error();
      _showMessage('終了できなかった。もう一度試してね');
      return false;
    }
  }

  Future<void> _changeMood() async {
    final viewModel = context.read<AppViewModel>();
    final current = viewModel.myHima;
    if (current == null) return;
    final mood = await showMoodPicker(context, current: current.mood);
    if (mood == null || mood == current.mood || !mounted) return;
    if (await applyMoodPick(viewModel, mood)) {
      if (mounted) AppHaptics.select();
      return;
    }
    if (!mounted) return;
    AppHaptics.error();
    _moodShakeKey.currentState?.shake();
    _showMessage('変更できなかった。もう一度試してね');
  }

  Future<void> _selectDuration(int minutes) async {
    final viewModel = context.read<AppViewModel>();
    if (await applyDurationPick(viewModel, minutes)) return;
    if (!mounted) return;
    AppHaptics.error();
    _durationShakeKey.currentState?.shake();
    _showMessage('変更できなかった。もう一度試してね');
  }

  Future<void> _selectActivity(Activity? activity) async {
    final viewModel = context.read<AppViewModel>();
    if (await applyActivityPick(viewModel, activity)) return;
    if (!mounted) return;
    AppHaptics.error();
    _activityShakeKey.currentState?.shake();
    _showMessage('変更できなかった。もう一度試してね');
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const KnocksScreen()));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  Future<void> _knock(UserSummary user, {Activity? activity, Mood? mood}) =>
      showKnockSheet(context, user: user, activity: activity, mood: mood);

  /// The match card, when there is a match.
  ///
  /// A card per person flooded the screen and repeated the people the friend
  /// grid already lists, so the friends of a kind share one card. Only 🙂×🙂
  /// matches exist, so there is a single card.
  List<MatchCard> _matchCards(
    List<MatchRecord> matches,
    Set<String> pendingUserIds,
    Set<String> acceptedUserIds,
  ) {
    if (matches.isEmpty) return const [];
    return [
      MatchCard(
        key: const ValueKey(MatchKind.okOk),
        kind: MatchKind.okOk,
        matches: matches,
        pendingUserIds: pendingUserIds,
        acceptedUserIds: acceptedUserIds,
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
    // A declaration from the notification's 「ひまにする」 skips the hero button,
    // so its landing effect is requested on the view model. It is taken after
    // the frame: build must not change state, and the hero needs the declared
    // session in place before the burst plays over it.
    if (viewModel.declareBurstPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !viewModel.takeDeclareBurst()) return;
        setState(() {
          _burstToken++;
          _justExpired = false;
        });
        AppHaptics.declare();
      });
    }
    final me = viewModel.me;
    final state = HeroState.fromSession(
      viewModel.myHima,
      justExpired: _justExpired,
      fallbackMood: viewModel.lastMood,
    );
    final pendingUserIds = viewModel.pendingKnockUserIds;
    final acceptedUserIds = viewModel.acceptedKnockUserIds;
    final matchCards = _matchCards(
      viewModel.matches,
      pendingUserIds,
      acceptedUserIds,
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppBottomNavigation.listBottomInset(context),
      ),
      children: [
        HomeHeader(
          hasKnockBadge: viewModel.hasUnseenKnocks,
          onOpenKnocks: _openKnocks,
          onOpenSettings: _openSettings,
        ),
        // The hero is a thick blob of paint. It throws its arms and droplets
        // into `paintThickBleed` of paper above and below, so its ragged edge
        // never touches a neighbouring card — whether or not match cards follow,
        // and at any text scale.
        const SizedBox(height: paintThickBleed),
        if (me != null)
          MyStatusHero(
            key: _heroKey,
            state: state,
            me: me,
            lastMood: viewModel.lastMood,
            selectedActivity: viewModel.selectedActivity,
            selectedDurationMin: viewModel.selectedDurationMin,
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
            onSelectDuration: _selectDuration,
            onSelectActivity: _selectActivity,
            onExpired: _handleExpired,
          ),
        if (matchCards.isEmpty)
          // No match cards: the hero's paint is the last thing above the
          // friends section, so it needs the same reserved band here too.
          const SizedBox(height: paintThickBleed)
        else ...[
          const SizedBox(height: paintThickBleed),
          for (final card in matchCards)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: card,
            ),
          // A wash only reaches a few dp past its box, so the standard section
          // gap is enough after the match cards.
          const SizedBox(height: AppSpacing.s24),
        ],
        FriendsSection(
          friends: viewModel.friends,
          pendingUserIds: pendingUserIds,
          acceptedUserIds: acceptedUserIds,
          loading: viewModel.isRefreshingLive,
          hasError: viewModel.hasLiveError,
          onRetry: () => unawaited(viewModel.refreshLiveData()),
          onKnock: (friend) =>
              _knock(friend.user, activity: friend.activity, mood: friend.mood),
        ),
      ],
    );
  }
}
