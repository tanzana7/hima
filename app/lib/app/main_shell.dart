import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_spacing.dart';
import '../app/theme/app_text_styles.dart';
import '../data/models/models.dart';
import '../features/friends/friends_screen.dart';
import '../features/home/home_screen.dart';
import '../features/knocks/knocks_screen.dart';
import '../features/profile/profile_screen.dart';
import '../shared/haptics.dart';
import '../shared/widgets/app_bottom_navigation.dart';
import '../shared/widgets/avatar_view.dart';
import '../shared/widgets/confetti_burst.dart';
import '../state/app_view_model.dart';

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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    super.dispose();
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
    _celebrationTimer = Timer(const Duration(seconds: 3), () {
      _dismissCelebration();
      // Another reply may have arrived while this one was on screen.
      _handleViewModelChanged();
    });
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

  void _dismissCelebration() {
    _celebrationTimer?.cancel();
    _celebrationTimer = null;
    if (!mounted) return;
    setState(() => _celebration = null);
  }

  void _openKnocks() {
    _dismissCelebration();
    // The knocks screen does not accept an initial tab, so this lands on 受信 and
    // the result is one tap away in 送信.
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const KnocksScreen()),
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
            ),
          ),
      ],
    );
  }
}

/// Celebration shown when a reply to a knock I sent arrives.
///
/// It fades in over whatever tab is open and disappears after a few seconds; the
/// confetti and the pop are decoration, so reduced motion keeps only the fade.
class _KnockResultOverlay extends StatelessWidget {
  const _KnockResultOverlay({
    super.key,
    required this.knock,
    required this.onTap,
  });

  final Knock knock;
  final VoidCallback onTap;

  String get _message {
    final name = knock.recipient?.displayName ?? '友達';
    return switch (knock.status) {
      KnockStatus.accepted => '$nameから いいよ！',
      KnockStatus.later => '$nameは あとでだって',
      KnockStatus.passed => '$nameは 今回はパスだって',
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
          if (accepted) const Positioned.fill(child: ConfettiBurst()),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              // Reduced motion keeps the fade and drops the pop.
              duration: Duration(milliseconds: reduceMotion ? 160 : 260),
              curve: Curves.easeOutBack,
              builder: (context, value, child) => Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: reduceMotion ? 1 : 0.85 + 0.15 * value,
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
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16 + 4,
                      vertical: AppSpacing.s16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                      border: Border.all(
                        color: accepted ? AppColors.coral : AppColors.purpleSoft,
                        width: AppSpacing.borderWidth,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.16),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AvatarView(
                          name: knock.recipient?.displayName ?? '友達',
                          imageUrl: knock.recipient?.avatarUrl,
                          size: 56,
                          background: AppColors.purpleSoft,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.friendName.copyWith(
                            fontSize: 16,
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
