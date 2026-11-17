import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/doodles.dart';
import '../../../shared/widgets/mood_badge.dart';
import '../../../shared/widgets/shake.dart';
import '../hero_state.dart';
import 'activity_chips.dart';
import 'declare_button.dart';

/// The hero card: the single most important area of the home screen.
///
/// Everything visual (backdrop, heading, meta row, actions) comes from
/// [HeroState], so the two states can never contradict each other.
///
/// The declared state is deliberately quiet: heading, one meta row, a small
/// exit. It used to stack a mood pill, a full-width end button and the chip row
/// under the heading, which buried the one thing worth reading.
class MyStatusHero extends StatefulWidget {
  const MyStatusHero({
    super.key,
    required this.state,
    required this.me,
    required this.lastMood,
    required this.selectedActivity,
    required this.busy,
    required this.burstToken,
    required this.shakeToken,
    required this.moodShakeKey,
    required this.durationShakeKey,
    required this.activityShakeKey,
    required this.showHint,
    required this.onDeclare,
    required this.onEnd,
    required this.onChangeMood,
    required this.onChangeDuration,
    required this.onSelectActivity,
    required this.onChangeActivity,
    required this.onExpired,
  });

  final HeroState state;
  final UserProfile me;
  final Mood lastMood;
  final Activity? selectedActivity;
  final bool busy;

  /// Bumped by the parent after a successful declaration to play the burst.
  final int burstToken;
  final int shakeToken;

  /// Shaken by the parent when saving the mood / the remaining time / the
  /// activity failed, so the control that failed is the one that moves.
  final GlobalKey<ShakeState> moodShakeKey;
  final GlobalKey<ShakeState> durationShakeKey;
  final GlobalKey<ShakeState> activityShakeKey;
  final bool showHint;
  final ValueChanged<Mood> onDeclare;
  final VoidCallback onEnd;
  final VoidCallback onChangeMood;
  final VoidCallback onChangeDuration;
  final ValueChanged<Activity?> onSelectActivity;

  /// Opens the activity picker from the declared meta row, where the chip row
  /// is hidden.
  final VoidCallback onChangeActivity;
  final VoidCallback onExpired;

  @override
  State<MyStatusHero> createState() => _MyStatusHeroState();
}

class _MyStatusHeroState extends State<MyStatusHero>
    with SingleTickerProviderStateMixin {
  /// Room for the doodles: they live in this band, outside the text.
  static const _padding = 20.0;

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

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          // The two states cross-fade their backdrop instead of swapping a
          // colour, so declaring reads as the card warming up.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: declared ? 0 : 1, end: declared ? 1 : 0),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => BlobBackdrop(
              colors: [
                Color.lerp(
                  AppColors.heroIdleTop,
                  AppColors.heroDeclaredTop,
                  value,
                )!,
                Color.lerp(
                  AppColors.heroIdleBottom,
                  AppColors.heroDeclaredBottom,
                  value,
                )!,
              ],
            ),
          ),
        ),
        // The marks sit in the padding band, so they can never land on the text
        // however far the text scale grows. They are drawn in palette colours
        // rather than white: the band is inside the blob, and white on the pale
        // idle wash is barely a mark at all.
        //
        // Keyed on the phase so they pop in again when the hero switches state:
        // a declaration is the moment worth celebrating.
        Positioned(
          top: 10,
          right: 10,
          child: Doodle(
            key: ValueKey('hero-sparks-$declared'),
            kind: DoodleKind.sparks,
            size: const Size(26, 20),
            // Yellow rather than coral: the corner sits on the declared
            // gradient, where a coral mark all but disappears.
            color: AppColors.yellow,
            tilt: 0.2,
          ),
        ),
        Positioned(
          top: 8,
          left: 2,
          child: Doodle(
            key: ValueKey('hero-bang-$declared'),
            kind: DoodleKind.bang,
            size: const Size(14, 18),
            color: AppColors.purple,
            tilt: -0.14,
            delay: const Duration(milliseconds: 70),
          ),
        ),
        Positioned(
          bottom: 10,
          left: 10,
          child: Doodle(
            key: ValueKey('hero-star-$declared'),
            kind: DoodleKind.star,
            size: const Size(16, 16),
            color: AppColors.yellow,
            tilt: -0.3,
            delay: const Duration(milliseconds: 140),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(_padding),
          child: _content(state, declared, reduceMotion),
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
    );
  }

  Widget _content(
    HeroState state,
    bool declared,
    bool reduceMotion,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (declared)
              _MoodAvatar(
                mood: state.mood,
                me: widget.me,
                shakeKey: widget.moodShakeKey,
                onTap: widget.onChangeMood,
              )
            else
              AvatarView(
                name: widget.me.displayName,
                imageUrl: widget.me.avatarUrl,
                size: 56,
                background: AppColors.surface,
                ring: AppColors.surface,
                ringWidth: 2,
              ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              // The heading stops short of the right edge so it never runs
              // under the spark doodle in the corner.
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Transform.rotate(
                        key: ValueKey(state.heading),
                        // A couple of degrees of tilt: the heading is a sticker
                        // on the blob, not a form label.
                        angle: declared ? -0.03 : 0,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          state.heading,
                          style: AppTextStyles.heroTitle.copyWith(
                            fontSize: 34,
                            color: declared ? AppColors.surface : AppColors.ink,
                            // White on coral is large bold text, so the shadow
                            // is there to hold the edge on the lighter part of
                            // the gradient rather than to decorate.
                            shadows: declared
                                ? const [
                                    Shadow(
                                      color: Color(0x332F124F),
                                      blurRadius: 10,
                                      offset: Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    if (declared)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Doodle(
                          kind: DoodleKind.squiggle,
                          size: const Size(116, 9),
                          color: AppColors.surface.withValues(alpha: 0.85),
                          delay: const Duration(milliseconds: 90),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 2),
                      Text(
                        state.supporting,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (declared) ...[
          const SizedBox(height: AppSpacing.s12),
          // One wrap: how long is left, what I want to do, and the way out. All
          // three stay tappable, so the mood and the activity are still
          // changeable without the extra pills the hero used to carry.
          //
          // The exit shares the wrap instead of taking a row of its own. Its own
          // row left the blob's bottom-left empty, made the hero taller than its
          // content, and put the pill in the corner where the outline cut it.
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
                key: widget.activityShakeKey,
                child: _ActivityPill(
                  activity: state.activity,
                  onTap: widget.onChangeActivity,
                ),
              ),
              _EndPill(onTap: widget.onEnd),
            ],
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.s16),
          DeclareButton(
            lastMood: widget.lastMood,
            busy: widget.busy,
            shakeToken: widget.shakeToken,
            onDeclare: widget.onDeclare,
          ),
          const SizedBox(height: AppSpacing.s8),
          // Optional and never a precondition for declaring, so it sits right
          // under the main button.
          Shake(
            key: widget.activityShakeKey,
            child: ActivityChips(
              selected: widget.selectedActivity,
              onSelected: widget.onSelectActivity,
            ),
          ),
          AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: widget.showHint
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
      ],
    );
  }
}

/// The avatar with the mood as a small badge on its corner.
///
/// The mood used to be a full pill next to the remaining time, which made the
/// declared hero a stack of equally loud pills. The emoji badge keeps the mood
/// visible and tappable while the heading stays the loudest thing in the card.
class _MoodAvatar extends StatelessWidget {
  const _MoodAvatar({
    required this.mood,
    required this.me,
    required this.shakeKey,
    required this.onTap,
  });

  final Mood mood;
  final UserProfile me;
  final GlobalKey<ShakeState> shakeKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Shake(
    key: shakeKey,
    child: SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AvatarView(
            name: me.displayName,
            imageUrl: me.avatarUrl,
            size: 56,
            background: AppColors.surface,
            ring: AppColors.surface,
            ringWidth: 2,
          ),
          Positioned(
            // Inside the avatar's box, not straddling its edge: a target that
            // hangs outside the parent is painted (Clip.none) but not hit
            // tested, which left only 40dp of the 48dp target reachable.
            right: 0,
            bottom: 0,
            // 48dp keeps the badge a valid tap target even though it is drawn
            // as a 26dp circle.
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            child: Semantics(
              button: true,
              label: '温度感を変更',
              hint: mood.label,
              // The tap action has to live on this node: `excludeSemantics`
              // drops the InkWell below, action included, so without it a
              // screen reader could announce the badge but not activate it.
              onTap: onTap,
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Padding(
                  // Nudged into the corner so the circle still reads as a badge
                  // on the avatar rather than one centred on it.
                  padding: const EdgeInsets.all(2),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: MoodBadge(mood: mood, size: 26, emojiSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shared shell of the small controls in the declared meta row.
///
/// It keeps a 48dp tap target and a 40dp minimum height but no fixed height, so
/// the label can grow with the text scale instead of being clipped.
class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      // Padding instead of a centred fixed box: the pill has to shrink-wrap so
      // the Wrap can lay the pills out from the heading's left edge, and the
      // padding still brings the tap target to 48dp. The horizontal padding is
      // the chip value from Design.md 3.3 rather than the card value: three
      // pills have to share one line on a 411dp screen.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: child,
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => _HeroPill(
    semanticsLabel: 'ひまの長さを変更',
    onTap: widget.onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule_rounded, size: 15, color: AppColors.ink),
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
  );
}

/// The activity as one compact pill: the selected one, or 「なにする？」 when the
/// optional choice is still open.
class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.activity, required this.onTap});

  final Activity? activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = activity == null ? null : ActivityStyle.of(activity!);
    return _HeroPill(
      semanticsLabel: activity == null ? 'やりたいことを選ぶ' : 'やりたいことを変更',
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            style?.icon ?? Icons.add_rounded,
            size: 15,
            color: style?.accent ?? AppColors.ink,
          ),
          const SizedBox(width: AppSpacing.s4),
          Flexible(
            child: Text(
              activity?.label ?? 'なにする？',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          const Icon(Icons.expand_more_rounded, size: 16, color: AppColors.ink),
        ],
      ),
    );
  }
}

/// 「おわる」: the quiet way out of a declaration.
///
/// It used to be a full-width white button, which competed with the heading and
/// the mood pill. It is now the last pill in the meta wrap: still a 48dp target
/// and still labelled for screen readers, but translucent and small enough that
/// it reads as a way out rather than as the point of the card.
class _EndPill extends StatelessWidget {
  const _EndPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'ひまを終了',
    // `excludeSemantics` drops the InkWell below, action included, so the node
    // carries the action itself or the exit is unreachable for screen readers.
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Center(
          // Shrink-wraps horizontally so the tap area is the pill, not the row.
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: AppColors.ink.withValues(alpha: 0.75),
                ),
                const SizedBox(width: AppSpacing.s4),
                Text(
                  'おわる',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink.withValues(alpha: 0.85),
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
