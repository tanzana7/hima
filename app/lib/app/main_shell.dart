import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_spacing.dart';
import '../app/theme/app_text_styles.dart';
import '../data/hima_suggest_bridge.dart';
import '../data/models/models.dart';
import '../features/friends/friends_screen.dart';
import '../features/home/declare_feedback.dart';
import '../features/home/home_screen.dart';
import '../features/home/widgets/pickers.dart';
import '../features/knocks/knocks_screen.dart';
import '../features/profile/profile_screen.dart';
import '../shared/haptics.dart';
import '../shared/widgets/app_bottom_navigation.dart';
import '../shared/widgets/avatar_view.dart';
import '../shared/widgets/confetti_burst.dart';
import '../state/app_view_model.dart';
import '../state/hima_suggest_controller.dart';

/// Three tabs with a fixed bottom navigation, plus the foreground polling that
/// keeps friends, matches and knocks fresh.
///
/// It also owns the reply overlay: a knock reply used to be invisible until the
/// user opened the bell and switched to 送信, so a new result is celebrated on
/// top of whichever tab is open.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  AppViewModel? _viewModel;
  HimaSuggestController? _suggest;

  /// True while a pending suggestion action is being read, so the shell's first
  /// frame, a resume and the channel callback cannot act on the same tap twice;
  /// a request that arrives meanwhile is flagged with [_checkQueued] so the read
  /// is repeated instead of dropped.
  bool _takingSuggestAction = false;
  bool _checkQueued = false;
  bool _checkedPendingAction = false;

  /// The reply currently on screen, and the timer that takes it away again.
  Knock? _celebration;
  Timer? _celebrationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.read<AppViewModel>();
    if (_viewModel != current) {
      _viewModel?.removeListener(_handleViewModelChanged);
      _viewModel?.stopPolling();
      _viewModel = current;
      current.addListener(_handleViewModelChanged);
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        current.startPolling();
      }
      // A reply that arrived while the app was closed is still unseen, but it
      // must not be shown from inside build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleViewModelChanged();
      });
    }
    final suggest = context.read<HimaSuggestController>();
    if (_suggest != suggest) {
      _suggest?.onAction = null;
      _suggest = suggest;
      suggest.onAction = () => unawaited(_checkPendingAction());
    }
    if (!_checkedPendingAction) {
      _checkedPendingAction = true;
      // The app may have been started by the notification, so the first frame is
      // checked as well as a resume.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkPendingAction());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A tap that arrived while the app was in the background is still stored
      // natively, so coming back is another chance to take it.
      unawaited(_checkPendingAction());
    }
    final viewModel = _viewModel;
    if (viewModel == null) return;
    if (state == AppLifecycleState.resumed) {
      viewModel.startPolling();
    } else {
      viewModel.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _celebrationTimer?.cancel();
    _viewModel?.removeListener(_handleViewModelChanged);
    _viewModel?.stopPolling();
    _suggest?.onAction = null;
    super.dispose();
  }

  /// Takes a pending 「いまひまじゃない？」 action, if there is one.
  ///
  /// The action is read through the channel instead of being taken from the
  /// notification, and reading consumes it: that is what keeps a single tap from
  /// declaring twice when the callback and a resume both fire.
  ///
  /// A request that arrives during a read is queued rather than dropped. A tap
  /// can land while the first frame or a resume is still awaiting the channel,
  /// and if that read answers null nothing else would look again until the app
  /// was backgrounded: the action would sit on the native side with no trigger.
  Future<void> _checkPendingAction() async {
    final suggest = _suggest;
    if (suggest == null) return;
    if (_takingSuggestAction) {
      _checkQueued = true;
      return;
    }
    _takingSuggestAction = true;
    try {
      do {
        _checkQueued = false;
        final action = await suggest.takePendingAction();
        if (!mounted) return;
        if (action == himaSuggestDeclareAction) {
          await _offerSuggestedDeclaration();
        }
      } while (_checkQueued && mounted);
    } catch (_) {
      // Nothing was taken; the next resume asks again.
    } finally {
      _takingSuggestAction = false;
    }
  }

  /// Opens the declaration the notification suggested.
  ///
  /// The worker never declares by itself: the suggestion only brings the user
  /// here, and the mood is still their choice.
  Future<void> _offerSuggestedDeclaration() async {
    final viewModel = context.read<AppViewModel>();
    // The declaration belongs to the home tab, and a pushed route would cover
    // the picker, so both go first.
    setState(() => _selectedIndex = 0);
    Navigator.of(context).popUntil((route) => route.isFirst);
    // Extending a live session is not what the suggestion offered.
    if (viewModel.isDeclared) return;
    final mood = await showMoodPicker(context, current: viewModel.lastMood);
    if (mood == null || !mounted) return;
    try {
      await viewModel.declareHima(
        mood: mood,
        source: DeclarationSource.suggested,
      );
      if (!mounted) return;
      unawaited(AppHaptics.declare());
    } catch (_) {
      if (!mounted) return;
      showDeclareFailure(context);
    }
  }

  void _handleViewModelChanged() {
    if (!mounted) return;
    _retrySeenMarks();
    if (_celebration != null) return;
    final result = _viewModel?.takeUnseenKnockResult();
    if (result == null) return;
    _showCelebration(result);
  }

  void _showCelebration(Knock result) {
    setState(() => _celebration = result);
    if (result.status == KnockStatus.accepted) {
      unawaited(AppHaptics.celebrate());
    } else {
      // A 「あとで」 / 「パス」 is information, not a win, so it only gets a
      // gentle tap.
      unawaited(AppHaptics.end());
    }
    _celebrationTimer?.cancel();
    // Four seconds: long enough to read a name and catch the confetti, short
    // enough that it never feels like a dialog to dismiss.
    _celebrationTimer = Timer(const Duration(seconds: 4), _dismissCelebration);
    // Marked seen as soon as it is shown, so the bell dot clears together with
    // the overlay instead of waiting for the 送信 tab.
    final viewModel = _viewModel;
    if (viewModel != null) unawaited(_markSeen(viewModel, result.id));
  }

  /// 「既読」 calls that failed. The result is already claimed for celebration, so
  /// a dropped call would leave it unseen forever; the next view model change
  /// (the foreground poll) tries again instead.
  final Set<String> _seenRetries = {};

  Future<void> _markSeen(AppViewModel viewModel, String knockId) async {
    try {
      await viewModel.markKnockResultSeen(knockId);
      _seenRetries.remove(knockId);
    } catch (_) {
      _seenRetries.add(knockId);
    }
  }

  void _retrySeenMarks() {
    if (_seenRetries.isEmpty) return;
    final viewModel = _viewModel;
    if (viewModel == null) return;
    for (final knockId in _seenRetries.toList()) {
      unawaited(_markSeen(viewModel, knockId));
    }
  }

  /// Takes the overlay away and, unless [keepNextQueued] is set, looks for the
  /// next queued reply so a second answer that arrived in the meantime is not
  /// left unseen.
  ///
  /// [keepNextQueued] is for the 送信 navigation: the pushed route covers the
  /// shell, and celebrating underneath it would mark the reply seen without
  /// anyone seeing it.
  void _dismissCelebration({bool keepNextQueued = false}) {
    _celebrationTimer?.cancel();
    _celebrationTimer = null;
    if (!mounted) return;
    setState(() => _celebration = null);
    if (!keepNextQueued) _handleViewModelChanged();
  }

  void _openKnocks() {
    _dismissCelebration(keepNextQueued: true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const KnocksScreen(showSentFirst: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_selectedIndex) {
      1 => const FriendsScreen(),
      2 => const ProfileScreen(),
      _ => const HomeScreen(),
    };
    final celebration = _celebration;
    return Stack(
      children: [
        Scaffold(
          // The navigation is not a bar any more: it is painted straight onto
          // the paper, so the scaffold background has to be the paper colour
          // and nothing may be tinted behind it.
          //
          // The body *is* extended under it, on purpose. Laying the body out
          // above the nav clipped every list on a ruler-straight line at the
          // nav's top edge, which is exactly the edge the paint look is meant
          // to remove. With `extendBody` the content scrolls underneath and the
          // nav's own transparent-to-paper fade dissolves it; each tab pads its
          // bottom by `AppBottomNavigation.listBottomInset` so the last item can
          // still be scrolled clear of the nav.
          backgroundColor: AppColors.background,
          extendBody: true,
          body: SafeArea(bottom: false, child: page),
          bottomNavigationBar: AppBottomNavigation(
            selectedIndex: _selectedIndex,
            onSelected: (index) => setState(() => _selectedIndex = index),
          ),
        ),
        if (celebration != null)
          Positioned.fill(
            child: _KnockResultOverlay(
              key: ValueKey(celebration.id),
              knock: celebration,
              onTap: _openKnocks,
              onDismiss: _dismissCelebration,
            ),
          ),
      ],
    );
  }
}

/// Celebration shown when a reply to a knock I sent arrives.
///
/// It covers whatever tab is open: a light scrim dims the app, the avatar pops
/// in, confetti crosses the whole screen for an 「いいよ！」, and the card leaves
/// after a few seconds. Tapping the card opens 送信; tapping or swiping down
/// outside it dismisses early. The confetti and the pop are decoration, so
/// reduced motion keeps only the fade.
class _KnockResultOverlay extends StatelessWidget {
  const _KnockResultOverlay({
    super.key,
    required this.knock,
    required this.onTap,
    required this.onDismiss,
  });

  final Knock knock;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  String get _message {
    final name = knock.recipient?.displayName ?? '友達';
    return switch (knock.status) {
      KnockStatus.accepted => '$nameから いいよ！',
      KnockStatus.later => '$nameは あとでだって',
      KnockStatus.passed => '$nameは 今回はパスだって',
      KnockStatus.expired => '$nameは いまはひまじゃないみたい',
      KnockStatus.pending => '$nameに さそった',
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accepted = knock.status == KnockStatus.accepted;
    // The overlay sits above the Scaffold, so it needs its own Material: without
    // one, Text falls back to the framework's placeholder style.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: _DismissScrim(
              reduceMotion: reduceMotion,
              onDismiss: onDismiss,
            ),
          ),
          if (accepted) const Positioned.fill(child: ConfettiBurst()),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              // Reduced motion keeps the fade and drops the pop.
              duration: Duration(milliseconds: reduceMotion ? 160 : 420),
              curve: reduceMotion ? Curves.easeOut : Curves.easeOutBack,
              builder: (context, value, child) => Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: reduceMotion ? 1 : 0.82 + 0.18 * value,
                  child: child,
                ),
              ),
              child: Semantics(
                button: true,
                label: '$_message。ノック画面を開く',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 360),
                    padding: const EdgeInsets.all(AppSpacing.s24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
                      border: Border.all(
                        color: accepted ? AppColors.coral : AppColors.purpleSoft,
                        width: AppSpacing.borderWidth * 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.22),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PoppingAvatar(
                          name: knock.recipient?.displayName ?? '友達',
                          imageUrl: knock.recipient?.avatarUrl,
                          reduceMotion: reduceMotion,
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.heroTitle.copyWith(
                            fontSize: 30,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light dim behind the card. Tapping it, or swiping down on it, dismisses the
/// celebration early; the card itself stays a single tap target that opens 送信.
class _DismissScrim extends StatelessWidget {
  const _DismissScrim({required this.reduceMotion, required this.onDismiss});

  final bool reduceMotion;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: 1),
    duration: Duration(milliseconds: reduceMotion ? 160 : 220),
    builder: (context, value, child) => Opacity(opacity: value, child: child),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onDismiss,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 120) onDismiss();
      },
      child: ColoredBox(color: AppColors.ink.withValues(alpha: 0.28)),
    ),
  );
}

/// The 72dp avatar with the celebratory pop. Reduced motion keeps it still.
class _PoppingAvatar extends StatelessWidget {
  const _PoppingAvatar({
    required this.name,
    required this.imageUrl,
    required this.reduceMotion,
  });

  final String name;
  final String? imageUrl;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarView(
      name: name,
      imageUrl: imageUrl,
      size: 72,
      background: AppColors.purpleSoft,
    );
    if (reduceMotion) return avatar;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 560),
      curve: Curves.elasticOut,
      builder: (context, value, child) =>
          Transform.scale(scale: 0.4 + 0.6 * value, child: child),
      child: avatar,
    );
  }
}
