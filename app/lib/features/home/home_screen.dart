import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_spacing.dart';
import '../../data/models/models.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/confetti_burst.dart';
import '../../state/app_view_model.dart';
import '../knocks/knocks_screen.dart';
import '../knocks/widgets/knock_sheet.dart';
import '../profile/settings_screen.dart';
import 'hero_state.dart';
import 'widgets/activity_chips.dart';
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
  bool _justExpired = false;
  Timer? _expiredTimer;
  bool _hintVisible = false;
  Timer? _hintTimer;
  bool _showConfetti = false;
  int _confettiToken = 0;

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
    final viewModel = context.read<AppViewModel>();
    _watchMatches(viewModel.matches);
    _watchKnockResults(viewModel);
    _primed = true;
  }

  @override
  void dispose() {
    _expiredTimer?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  /// The first frame only records what already exists so opening the app does
  /// not replay haptics for old matches and replies.
  void _watchMatches(List<MatchRecord> matches) {
    final fresh = matches
        .map((match) => match.id)
        .where(_seenMatchIds.add)
        .toList();
    if (!_primed || fresh.isEmpty) return;
    AppHaptics.match();
  }

  void _watchKnockResults(AppViewModel viewModel) {
    if (!_primed) return;
    // The claim lives in the view model so the sent tab does not celebrate the
    // same accepted result a second time.
    final fresh = viewModel.sent
        .where(
          (knock) =>
              knock.status == KnockStatus.accepted &&
              knock.resultSeenAt == null,
        )
        .where((knock) => viewModel.claimResultCelebration(knock.id))
        .toList();
    if (fresh.isEmpty) return;
    AppHaptics.celebrate();
    _confettiToken++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showConfetti = true);
    });
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

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final me = viewModel.me;
    final state = HeroState.fromSession(
      viewModel.myHima,
      justExpired: _justExpired,
      fallbackMood: viewModel.lastMood,
    );
    return Stack(
      children: [
        ListView(
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
                busy: _busy,
                burstToken: _burstToken,
                shakeToken: _shakeToken,
                showHint: _hintVisible,
                onDeclare: _declare,
                onEnd: _end,
                onChangeMood: _changeMood,
                onChangeDuration: _changeDuration,
                onExpired: _handleExpired,
              ),
            if (me != null && viewModel.matches.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s24),
              for (final match in viewModel.matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                  child: MatchCard(
                    key: ValueKey(match.id),
                    match: match,
                    me: me,
                    onKnock: () => _knock(
                      match.otherUser,
                      activity: match.otherHima.activity,
                      mood: match.otherHima.mood,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.s24),
            FriendsSection(
              friends: viewModel.friends,
              loading: viewModel.isRefreshingLive,
              hasError: viewModel.hasLiveError,
              onRetry: () => unawaited(viewModel.refreshLiveData()),
              onKnock: (friend) => _knock(
                friend.user,
                activity: friend.activity,
                mood: friend.mood,
              ),
            ),
            const SizedBox(height: AppSpacing.s32),
            ActivityChips(
              selected: viewModel.selectedActivity,
              onSelected: _selectActivity,
            ),
          ],
        ),
        if (_showConfetti)
          Positioned.fill(
            child: ConfettiBurst(
              key: ValueKey(_confettiToken),
              onCompleted: () {
                if (mounted) setState(() => _showConfetti = false);
              },
            ),
          ),
      ],
    );
  }
}
