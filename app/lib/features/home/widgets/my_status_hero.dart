import 'dart:async';

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
import 'hero_paint.dart';

/// The hero: the single most important area of the home screen.
///
/// Everything visual (paint, heading, meta row, actions) comes from [HeroState],
/// so the two states can never contradict each other.
///
/// The paint is one thick blob, not a band: a band reads as a rectangle seen
/// from the side, and the heading is meant to sit on a lump of paint. Both
/// states are painted with the same seed, so the declared paint covers the paper
/// state exactly; that is what lets the wipe reveal the paper state under it
/// instead of a second, slightly different blob.
///
/// **Stable height.** The paper and the declared layer are laid out together
/// while the paint is coming off, and [AnimatedSize] closes the difference
/// afterwards, so the cards below do not jump between the two states.
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

  /// Bumped by the parent after a successful declaration to play the landing.
  final int burstToken;
  final int shakeToken;

  /// Shaken by the parent when saving the mood / the remaining time / the
  /// activity failed, so the control that failed is the one that moves.
  final GlobalKey<ShakeState> moodShakeKey;
  final GlobalKey<ShakeState> durationShakeKey;
  final GlobalKey<ShakeState> activityShakeKey;
  final bool showHint;
  final ValueChanged<Mood> onDeclare;

  /// Ends the declaration and answers whether the server accepted it.
  ///
  /// The answer is what decides the wipe: on success the paint stays off, on
  /// failure the declared state comes back exactly as it was instead of the
  /// screen flashing the paper state and then the declared one again.
  final Future<bool> Function() onEnd;
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
    with TickerProviderStateMixin {
  /// How long the stroke takes to reach [_wipeHold]: long enough to read as a
  /// brush drag, short enough that the screen is not held up by it. Together
  /// with [_wipeFinishDuration] it is the ~700ms the end takes when the server
  /// answers at once.
  static const _wipeDuration = Duration(milliseconds: 560);

  /// Where the stroke parks while the end is still open.
  ///
  /// The paper state has to stay covered until the server has accepted the end:
  /// a request that fails after the paint is gone would have flashed OFF and
  /// back to ON. So the stroke stops one strip short of the end and only the
  /// answer takes the rest of the paint off.
  static const _wipeHold = 0.88;

  /// The last strip of paint, taken off once the end has been accepted.
  static const _wipeFinishDuration = Duration(milliseconds: 140);

  /// The paint being put back after a failed end never takes longer than a beat.
  static const _restoreDuration = Duration(milliseconds: 260);

  late final AnimationController _burst;
  late final AnimationController _wipe;

  bool _bursting = false;
  bool _ending = false;

  /// The declared state the wipe started from. It keeps the heading, the meta
  /// row and the mood under the brush for as long as the paint is coming off,
  /// however early or late the request answers.
  HeroState? _endingState;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy `late` field would be constructed from dispose()
    // when no animation ever ran, which is not a safe time to make a Ticker.
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _wipe = AnimationController(vsync: this, duration: _wipeDuration);
  }

  @override
  void didUpdateWidget(MyStatusHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.burstToken != oldWidget.burstToken &&
        !MediaQuery.disableAnimationsOf(context)) {
      setState(() => _bursting = true);
      _burst.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _bursting = false);
      });
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    _wipe.dispose();
    super.dispose();
  }

  /// 「おわる」: the only way the paint ever comes off.
  ///
  /// The stroke runs over the still-declared state, and the request goes out at
  /// the same time, so the tap answers at once. It stops at [_wipeHold] until
  /// the end is accepted: only a finished wipe *and* an accepted end reveal the
  /// paper state, so a failure never flashes OFF and back to ON. An expiry or a
  /// server-driven change never runs this, so their behaviour is unchanged.
  Future<void> _handleEnd() async {
    if (_ending || widget.busy) return;
    if (!widget.state.isDeclared) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduced motion: no stroke to run, the state changes on its own.
      await widget.onEnd();
      return;
    }
    setState(() {
      _ending = true;
      _endingState = widget.state;
    });
    final stroke = _wipe.animateTo(
      _wipeHold,
      duration: _wipeDuration,
      curve: Curves.easeOutCubic,
    );
    final ended = await widget.onEnd();
    if (!mounted) return;
    if (ended) {
      // The answer is yes: take the last strip off now. The paint is only
      // fully gone once this finishes, which is what keeps the paper state
      // hidden for as long as the end was unconfirmed.
      await stroke;
      if (!mounted) return;
      await _wipe.animateTo(
        1,
        duration: _wipeFinishDuration,
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      setState(() => _ending = false);
      _endingState = null;
      _wipe.value = 0;
      return;
    }
    // The declaration is still live, so the paint goes back on. It is restored
    // from the same controller, which is what keeps a failed end from flashing
    // the paper state and then the declared one again.
    await _wipe.animateBack(
      0,
      duration: _restoreDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() => _ending = false);
    _endingState = null;
  }

  /// The paper state behind the declared one.
  ///
  /// While the paint is coming off, the state is still declared (or has just
  /// stopped being so), and the heading under the brush must be the one the user
  /// will be left with.
  HeroState _paperState(HeroState state) => state.isDeclared
      ? HeroState.fromSession(
          null,
          justExpired: false,
          fallbackMood: state.mood,
        )
      : state;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final state = widget.state;
    final declared = state.isDeclared;
    final onState = _ending ? (_endingState ?? state) : state;
    final showPaint = declared || _ending;
    final showPaper = !declared || _ending;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topLeft,
            children: [
              // The paper the declared paint is laid over. Painted first so the
              // wipe has something to reveal, and the same silhouette, so it
              // never shows around the declared blob's edge.
              if (showPaint)
                Positioned.fill(
                  key: const ValueKey('paper-paint'),
                  child: const HeroIdlePaint(),
                ),
              // The paper content. It sizes the hero whenever it is the visible
              // picture, so the heading and the label sit on the paint instead
              // of on paper left over from the other state.
              if (showPaper) _paperLayer(state),
              if (showPaint)
                // The paint and the content it carries take the same wipe front
                // from the same ticker, so the white heading can never be left
                // on the paper state the brush has already uncovered. Both the
                // landing and the wipe are driven from here: nothing else
                // rebuilds the hero while a controller runs.
                AnimatedBuilder(
                  key: const ValueKey('declared-layer'),
                  animation: Listenable.merge([_burst, _wipe]),
                  builder: (context, _) {
                    final front = _ending
                        ? _wipe.value.clamp(0.0, 1.0).toDouble()
                        : 0.0;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: HeroPaint(
                            colors: heroDeclaredColors,
                            progress: _bursting ? _burst.value : 1,
                            wipe: front,
                            // White heading on coral: the bristles stay in the
                            // paint's edge band so they cannot lift the fill
                            // under the text below its 3:1.
                            detailUnderContent: 0.2,
                          ),
                        ),
                        _declaredLayer(onState, front),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        // The chips sit on the paper below the blob, not on it: inside the paint
        // the scrolling row was cut by the shape's edge, and a fade over that
        // edge would have taken the chip labels' contrast with it.
        if (!declared) ...[
          const SizedBox(height: AppSpacing.s8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            // Optional and never a precondition for declaring, so it sits right
            // under the hero.
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
  }

  /// The undeclared picture: the declare surface, or — while the paint is being
  /// wiped off — the same content as the picture underneath.
  ///
  /// The content is unpadded here: the declare surface's paint applies
  /// [heroBlobPadding] to it, and the inert copy under the wipe pads it itself,
  /// so both states keep exactly one inset.
  Widget _paperLayer(HeroState state) {
    final content = _offContent(_paperState(state));
    if (!_ending) {
      return DeclareButton(
        lastMood: widget.lastMood,
        busy: widget.busy,
        shakeToken: widget.shakeToken,
        onDeclare: widget.onDeclare,
        child: content,
      );
    }
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Padding(padding: heroBlobPadding, child: content),
      ),
    );
  }

  Widget _declaredLayer(HeroState state, double wipe) {
    final content = IgnorePointer(
      ignoring: _ending,
      child: ExcludeSemantics(
        excluding: _ending,
        // The declared paint has no child, so the inset is applied here — once,
        // with the same value the paper state gets, so neither layout is
        // narrower than the other.
        child: Padding(padding: heroBlobPadding, child: _onContent(state)),
      ),
    );
    if (wipe <= 0) return content;
    // The content is clipped by the same front the paint is: white text must
    // never sit on the paper state left behind by the wipe.
    return ClipPath(
      clipper: _WipeClipper(progress: wipe, seed: heroBlobSeed),
      child: content,
    );
  }

  /// The undeclared content: who I am, the question, and the one thing to do.
  ///
  /// It carries no padding: the declare surface's paint applies [heroBlobPadding]
  /// to it, and so does the inert copy the wipe reveals, so the two pictures keep
  /// the same single inset.
  Widget _offContent(HeroState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.heading,
                    style: AppTextStyles.heroTitle.copyWith(
                      fontSize: 34,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.supporting,
                    // [AppColors.muted] drops to about 4.2:1 over the lavender
                    // stop of the idle paint. Translucent ink stays
                    // secondary-looking but keeps about 6:1.
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        // The label is the only thing that says the paint is a button, so it is
        // centred on the blob and always in view — it is not a second control,
        // the whole blob answers the tap.
        Center(child: _TapLabel(busy: widget.busy)),
        if (widget.showHint) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            '長押しで温度感を選べるよ',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.ink.withValues(alpha: 0.72),
            ),
          ),
        ],
      ],
    );
  }

  /// The declared content: the mood on the avatar, the heading, one meta row.
  ///
  /// Unpadded like [_offContent]; the declared layer applies [heroBlobPadding],
  /// so neither state is laid out narrower than the other.
  Widget _onContent(HeroState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MoodAvatar(
              mood: state.mood,
              me: widget.me,
              shakeKey: widget.moodShakeKey,
              onTap: widget.onChangeMood,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    // A couple of degrees of tilt: the heading is painted on
                    // the blob, not set like a form label.
                    angle: -0.03,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      state.heading,
                      style: AppTextStyles.heroTitle.copyWith(
                        fontSize: 34,
                        color: AppColors.surface,
                        // 34sp bold is WCAG large text, so white needs 3:1
                        // here, not 4.5:1. The coral stops are chosen for that
                        // (3.8:1 and 3.4:1), and the paint makes sure the
                        // bristles never lift them: the shadow only holds the
                        // edge on the lighter end of the gradient.
                        shadows: const [
                          Shadow(
                            color: Color(0x332F124F),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    // A brush stroke rather than a thin squiggle: thick in the
                    // middle and tapering at both ends.
                    child: BrushStroke(
                      seed: 23,
                      size: const Size(116, 9),
                      color: AppColors.surface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        // One wrap: how long is left, what I want to do, and the way out. All
        // three stay tappable, so the mood and the activity are still
        // changeable without the extra pills the hero used to carry.
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
            _EndPill(onTap: _handleEnd),
          ],
        ),
      ],
    );
  }
}

/// Clips the declared content to the paint the wipe has left behind.
class _WipeClipper extends CustomClipper<Path> {
  const _WipeClipper({required this.progress, required this.seed});

  final double progress;
  final int seed;

  @override
  Path getClip(Size size) =>
      paintWipeKeptPath(size: size, progress: progress, seed: seed);

  @override
  bool shouldReclip(_WipeClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.seed != seed;
}

/// `タップで宣言`: the one label that makes the paint discoverable.
///
/// It sits on a white dab because the idle paint is a pastel wash: small ink
/// text on it keeps its contrast, and white text on pale paint would not
/// (Design.md 3.1).
class _TapLabel extends StatelessWidget {
  const _TapLabel({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) => PaintDab(
    seed: 4242,
    color: AppColors.surface.withValues(alpha: 0.95),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    wobble: 0.09,
    droplets: 1,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.ink,
            ),
          )
        else
          const Icon(Icons.touch_app_rounded, size: 20, color: AppColors.ink),
        const SizedBox(width: AppSpacing.s8),
        Flexible(
          child: Text(
            'タップで宣言',
            textAlign: TextAlign.center,
            style: AppTextStyles.button.copyWith(fontSize: 17),
          ),
        ),
      ],
    ),
  );
}

/// The avatar with the mood as a small badge on its corner.
///
/// The emoji badge keeps the mood visible and tappable while the heading stays
/// the loudest thing in the blob.
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
/// background is a paint dab, not a stadium: on the thick blob a perfect pill
/// would be the last vector shape in the hero.
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
      // padding still brings the tap target to 48dp.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: PaintDab(
          seed: seed,
          color: AppColors.surface.withValues(alpha: 0.94),
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
            himaRemainingShortLabel(widget.expiresAt),
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
/// It is the last pill in the meta wrap: still a 48dp target and still labelled
/// for screen readers, but translucent and small enough that it reads as a way
/// out rather than as the point of the blob. It is also the only thing that
/// starts the wipe.
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
