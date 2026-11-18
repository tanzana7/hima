import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/mood_badge.dart';
import '../../../shared/widgets/paint/paint.dart';
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
  /// The band the paint keeps clear of the content. Everything the user can
  /// read or tap stays inside the rect this leaves, so the strands, the dry
  /// streaks and the splatter can never cover it.
  ///
  /// The vertical inset is tighter than the horizontal one: the band should
  /// read as a band, not as a flag, and the content already carries its own
  /// 48dp targets.
  static const _padding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

  /// Fixed seeds: the hero's two strokes must not change shape between
  /// rebuilds, and the declared one has to sit over the idle one every time.
  static const _idleSeed = 20261117;
  static const _declaredSeed = 71119;

  late final AnimationController _burstController;
  bool _bursting = false;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy `late` field would be constructed from dispose()
    // when no burst ever ran, which is not a safe time to make a Ticker.
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
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
    // Reduced motion can switch on while the declare animation is running. The
    // stroke then paints itself whole at once, so the outer clip and the idle
    // band have to jump to the finished state with it instead of staying at the
    // in-progress value.
    final bursting = _bursting && !reduceMotion;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The paper the stroke keeps for its dry end and its splatter. It is a
        // floor on the content's right padding, not an addition to it: the two
        // used to be summed, which pushed the content — and the declare button
        // under it — about 25dp left of the stroke's own centre. Both strokes
        // get the same value so their silhouettes line up.
        final contentInset = math.max(
          _padding.right,
          paintSwipeContentInset(constraints.maxWidth),
        );
        // The content rect is inset on the right only, so its centre sits left
        // of the box centre by half the difference. The declare button and its
        // hint are centred on the box instead, to share the axis of the centred
        // cards and chips below them; the rest of the hero stays left-aligned.
        final centerOffset = math.max(0.0, contentInset - _padding.left);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // The idle stroke. It stays visible while the coral paints itself
                // in over it, and fades out once the coral has landed: the coral
                // covers the content rect but not the idle strands, so a stroke
                // left underneath would keep lavender and lemon strands peeking out
                // around it as a leftover layer.
                //
                // Reduced motion drops the fade and switches it off at once.
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: declared && !bursting ? 0 : 1,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    child: BrushSwipe(
                      seed: _idleSeed,
                      colors: const [
                        AppColors.heroIdleTop,
                        AppColors.heroIdleBottom,
                      ],
                      padding: _padding,
                      endInset: contentInset,
                      droplets: 12,
                    ),
                  ),
                ),
                if (declared)
                  // The coral stroke paints *itself* in from the left over the idle
                  // one, and its splatter flicks as the brush reaches the end. It is
                  // not an overlay on a finished stroke: the stroke is the thing
                  // being painted.
                  //
                  // Painting it in would normally leave the white heading on the
                  // pale idle stroke until the front reached it, so the content is
                  // clipped by the same front below — the text is only ever drawn
                  // where the coral already is.
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _burstController,
                      builder: (context, _) => BrushSwipe(
                        seed: _declaredSeed,
                        colors: const [
                          AppColors.heroDeclaredTop,
                          AppColors.heroDeclaredBottom,
                        ],
                        padding: _padding,
                        endInset: contentInset,
                        droplets: 16,
                        progress: bursting ? _burstController.value : 1,
                      ),
                    ),
                  ),
                // The mark sits in the paper the stroke leaves around the
                // content, so it can never land on the text however far the text
                // scale grows. It is drawn in a palette colour rather than
                // white: white on the pale idle stroke is barely a mark at all.
                //
                // Only the bottom-left star is left. The top-right splatter dots
                // that used to sit here landed on the same side as the stroke's
                // own splatter, which made the right end read as twice as busy
                // as the left; the stroke already carries that corner.
                //
                // Keyed on the phase so it reappears when the hero switches
                // state: a declaration is the moment worth celebrating.
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: PaintMark(
                    key: ValueKey('hero-star-$declared'),
                    kind: PaintMarkKind.star,
                    seed: 9,
                    color: AppColors.yellow,
                    size: 16,
                  ),
                ),
                // The content ends where the dry end begins: the same inset the
                // stroke uses, so the strands and the streaks are never under a
                // label.
                _revealWithPaint(
                  Padding(
                    padding: _padding.copyWith(right: contentInset),
                    child: _content(
                      state,
                      declared,
                      reduceMotion,
                      centerOffset,
                    ),
                  ),
                  bursting,
                ),
              ],
            ),
            // The chips sit on the paper below the stroke, not on it. Inside the
            // band the scrolling row was cut by the band's straight right edge,
            // and a fade over that edge would have taken the chip labels'
            // contrast with it. On paper every label stays fully opaque.
            if (!declared) ...[
              const SizedBox(height: AppSpacing.s8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                // Optional and never a precondition for declaring, so it sits
                // right under the card.
                child: Shake(
                  key: widget.activityShakeKey,
                  child: ActivityChips(
                    selected: widget.selectedActivity,
                    onSelected: widget.onSelectActivity,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Clips [child] to the paint front while the declared stroke is painting
  /// itself in.
  ///
  /// The heading is white and the idle stroke is pale lavender, so a heading
  /// drawn ahead of the coral would drop to about 1.1:1 for as long as the
  /// brush takes to reach it. Clipping the content with the same path the
  /// stroke is clipped with keeps the text on paint at every frame — and reads
  /// as the brush painting the new state in.
  ///
  /// [bursting] is already false under reduced motion, so a mid-animation
  /// switch to reduced motion drops the clip instead of leaving the content cut
  /// at the in-progress value.
  Widget _revealWithPaint(Widget child, bool bursting) {
    if (!bursting) return child;
    return AnimatedBuilder(
      animation: _burstController,
      // The content subtree is passed through untouched: only the clip
      // changes per frame.
      child: child,
      builder: (context, child) => ClipPath(
        clipper: _SwipeRevealClipper(
          progress: _burstController.value,
          seed: _declaredSeed,
        ),
        child: child,
      ),
    );
  }

  Widget _content(
    HeroState state,
    bool declared,
    bool reduceMotion,
    double centerOffset,
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
              // No right padding here: the content is already inset by the
              // stroke's dry end, which is past the fingers and the streaks, so
              // the heading cannot run under them.
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
                          // 34sp bold is WCAG large text, so white needs
                          // 3:1 here, not 4.5:1. The coral stops are chosen
                          // for that (3.8:1 and 3.4:1); the shadow only holds
                          // the edge on the lighter end of the gradient.
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
                      // A brush stroke rather than a thin squiggle: the
                      // underline is paint now, thick in the middle and
                      // tapering at both ends.
                      child: BrushStroke(
                        seed: 23,
                        size: const Size(116, 9),
                        color: AppColors.surface.withValues(alpha: 0.85),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 2),
                    Text(
                      state.supporting,
                      // [AppColors.muted] drops to about 4.2:1 over the
                      // lavender stop of the idle stroke. Translucent ink
                      // stays secondary-looking but keeps about 6:1.
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (declared) ...[
          const SizedBox(height: AppSpacing.s8),
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
          // The primary action and its hint are centred on the stroke's box,
          // not on the content rect. The rect is inset by the dry end on the
          // right only, so centring inside it put the one thing the screen is
          // asking for about 25dp left of the screen centre. The button gives up
          // the difference in width; it stays the widest thing in the card.
          Padding(
            padding: EdgeInsets.only(left: centerOffset),
            child: DeclareButton(
              lastMood: widget.lastMood,
              busy: widget.busy,
              shakeToken: widget.shakeToken,
              onDeclare: widget.onDeclare,
            ),
          ),
          AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: widget.showHint
                ? Padding(
                    key: const ValueKey('hint'),
                    padding: EdgeInsets.only(
                      top: AppSpacing.s8,
                      left: centerOffset,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Ink at 72%, not [AppColors.muted]: muted is 4.18:1 on
                        // the lavender stop of the idle wash and stays under
                        // 4.5:1 across most of the gradient, which is not enough
                        // for a 13sp caption. This pair is about 6:1 on both
                        // stops, and it matches the supporting copy above.
                        Icon(
                          Icons.touch_app_outlined,
                          size: 14,
                          color: AppColors.ink.withValues(alpha: 0.72),
                        ),
                        const SizedBox(width: AppSpacing.s4),
                        Flexible(
                          child: Text(
                            '長押しで温度感を選べるよ',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.ink.withValues(alpha: 0.72),
                            ),
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

/// Clips the hero's content to the declared stroke's paint front.
///
/// It is the same path the stroke itself is clipped with, so the text appears
/// exactly where the paint has arrived and never on the pale idle stroke ahead
/// of it.
class _SwipeRevealClipper extends CustomClipper<Path> {
  const _SwipeRevealClipper({required this.progress, required this.seed});

  final double progress;
  final int seed;

  @override
  Path getClip(Size size) =>
      paintSwipeRevealPath(size: size, progress: progress, seed: seed);

  @override
  bool shouldReclip(_SwipeRevealClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.seed != seed;
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
/// the label can grow with the text scale instead of being clipped. The white
/// background is a paint dab, not a stadium: on the coral splash a perfect pill
/// was the last vector shape left in the hero.
class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.seed,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
  });

  final int seed;
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
        child: PaintDab(
          seed: seed,
          color: AppColors.surface.withValues(alpha: 0.92),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          // The dab is only ~40dp tall, so the wobble has to be a larger
          // fraction of the short side than a card's to show at all.
          wobble: 0.09,
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
    seed: 61,
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
      seed: 62,
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
          child: PaintDab(
            seed: 63,
            color: AppColors.surface.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            wobble: 0.10,
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

