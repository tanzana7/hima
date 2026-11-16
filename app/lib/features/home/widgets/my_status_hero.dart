import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/shake.dart';
import '../hero_state.dart';
import 'declare_button.dart';

/// The hero card: the single most important area of the home screen.
///
/// Everything visual (background, heading, supporting line, buttons) comes from
/// [HeroState], so the two states can never contradict each other.
class MyStatusHero extends StatefulWidget {
  const MyStatusHero({
    super.key,
    required this.state,
    required this.me,
    required this.lastMood,
    required this.busy,
    required this.burstToken,
    required this.shakeToken,
    required this.moodShakeKey,
    required this.durationShakeKey,
    required this.showHint,
    required this.onDeclare,
    required this.onEnd,
    required this.onChangeMood,
    required this.onChangeDuration,
    required this.onExpired,
  });

  final HeroState state;
  final UserProfile me;
  final Mood lastMood;
  final bool busy;

  /// Bumped by the parent after a successful declaration to play the burst.
  final int burstToken;
  final int shakeToken;

  /// Shaken by the parent when saving the mood / the remaining time failed, so
  /// the control that failed is the one that moves.
  final GlobalKey<ShakeState> moodShakeKey;
  final GlobalKey<ShakeState> durationShakeKey;
  final bool showHint;
  final ValueChanged<Mood> onDeclare;
  final VoidCallback onEnd;
  final VoidCallback onChangeMood;
  final VoidCallback onChangeDuration;
  final VoidCallback onExpired;

  @override
  State<MyStatusHero> createState() => _MyStatusHeroState();
}

class _MyStatusHeroState extends State<MyStatusHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burstController;
  bool _bursting = false;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy `late` field would be constructed from dispose()
    // when no burst ever ran, which is not a safe time to make a Ticker.
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void didUpdateWidget(MyStatusHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.burstToken != oldWidget.burstToken &&
        !MediaQuery.disableAnimationsOf(context)) {
      setState(() => _bursting = true);
      _burstController.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _bursting = false);
      });
    }
  }

  @override
  void dispose() {
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final declared = state.isDeclared;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(AppSpacing.s16 + 4),
      decoration: BoxDecoration(
        color: declared
            ? AppColors.coral
            : AppColors.purpleSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarView(
                    name: widget.me.displayName,
                    imageUrl: widget.me.avatarUrl,
                    size: 60,
                    background: AppColors.surface,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.35),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            state.heading,
                            key: ValueKey(state.heading),
                            style: AppTextStyles.heroTitle.copyWith(
                              fontSize: 34,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        if (!declared)
                          Text(
                            state.supporting,
                            style: AppTextStyles.body.copyWith(
                              color: declared ? AppColors.ink : AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (declared) ...[
                const SizedBox(height: AppSpacing.s12),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Shake(
                      key: widget.durationShakeKey,
                      child: _RemainingPill(
                        expiresAt: state.expiresAt!,
                        onTap: widget.onChangeDuration,
                        onExpired: widget.onExpired,
                      ),
                    ),
                    Shake(
                      key: widget.moodShakeKey,
                      child: _MoodBadge(
                        mood: state.mood,
                        onTap: widget.onChangeMood,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.s16),
              if (declared)
                _SecondaryPill(
                  label: 'ひまを終了',
                  icon: Icons.flag_outlined,
                  onTap: widget.onEnd,
                )
              else
                DeclareButton(
                  lastMood: widget.lastMood,
                  busy: widget.busy,
                  shakeToken: widget.shakeToken,
                  onDeclare: widget.onDeclare,
                ),
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: !declared && widget.showHint
                    ? Padding(
                        key: const ValueKey('hint'),
                        padding: const EdgeInsets.only(top: AppSpacing.s8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.touch_app_outlined,
                              size: 14,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: AppSpacing.s4),
                            Flexible(
                              child: Text(
                                '長押しで温度感を選べるよ',
                                style: AppTextStyles.caption,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-hint')),
              ),
            ],
          ),
          if (_bursting)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _burstController,
                    builder: (context, _) => CustomPaint(
                      painter: _HeroBurstPainter(
                        progress: _burstController.value,
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

class _RemainingPill extends StatefulWidget {
  const _RemainingPill({
    required this.expiresAt,
    required this.onTap,
    required this.onExpired,
  });

  final DateTime expiresAt;
  final VoidCallback onTap;
  final VoidCallback onExpired;

  @override
  State<_RemainingPill> createState() => _RemainingPillState();
}

class _RemainingPillState extends State<_RemainingPill> {
  Timer? _timer;
  bool _reportedExpiry = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final remaining = widget.expiresAt.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero && !_reportedExpiry) {
        _reportedExpiry = true;
        widget.onExpired();
      }
    });
  }

  @override
  void didUpdateWidget(_RemainingPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expiresAt != oldWidget.expiresAt) {
      _reportedExpiry = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'ひまの長さを変更',
    child: InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: SizedBox(
        height: AppSpacing.minTapTarget,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 15,
                  color: AppColors.ink,
                ),
                const SizedBox(width: AppSpacing.s4),
                Flexible(
                  child: Text(
                    himaRemainingLabel(widget.expiresAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MoodBadge extends StatelessWidget {
  const _MoodBadge({required this.mood, required this.onTap});

  final Mood mood;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '温度感を変更',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: SizedBox(
        height: AppSpacing.minTapTarget,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mood.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: AppSpacing.s4),
                Flexible(
                  child: Text(
                    mood.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: AppColors.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SecondaryPill extends StatelessWidget {
  const _SecondaryPill({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: AppColors.purpleSoft,
            width: AppSpacing.borderWidth,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppColors.ink),
            const SizedBox(width: AppSpacing.s8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.button.copyWith(fontSize: 17),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HeroBurstPainter extends CustomPainter {
  _HeroBurstPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final linePaint = Paint()
      ..color = AppColors.yellow.withValues(alpha: fade)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final inner = size.shortestSide * (0.30 + progress * 0.10);
    final outer = inner + size.shortestSide * 0.10 * (1 - progress);
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi * 2 / 12;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * inner,
        center + direction * outer,
        linePaint,
      );
    }
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 5 + 0.3;
      final distance = size.shortestSide * (0.2 + progress * 0.38);
      final position =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      _drawStar(
        canvas,
        position,
        2 + 5 * (1 - progress),
        AppColors.surface.withValues(alpha: fade),
      );
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final r = i.isEven ? radius : radius * 0.34;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HeroBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
