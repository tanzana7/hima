import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/phrase_wrap.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/mood_badge.dart';
import '../../../shared/widgets/paint/paint.dart';
import '../../../shared/widgets/shake.dart';
import '../hero_state.dart';
import 'activity_chips.dart';
import 'declare_button.dart';
import 'hero_paint.dart';
import 'pickers.dart';

enum HeroInlinePicker { activity, duration }

/// The home hero. Its state, paint, and controls change together so the OFF
/// question and ON declaration can never contradict each other.
class MyStatusHero extends StatefulWidget {
  const MyStatusHero({
    super.key,
    required this.state,
    required this.me,
    required this.lastMood,
    required this.selectedActivity,
    required this.selectedDurationMin,
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
    required this.onSelectDuration,
    required this.onSelectActivity,
    required this.onExpired,
  });

  final HeroState state;
  final UserProfile me;
  final Mood lastMood;
  final Activity? selectedActivity;
  final int selectedDurationMin;
  final bool busy;

  /// Bumped by the parent after a successful declaration to play the landing.
  final int burstToken;
  final int shakeToken;

  final GlobalKey<ShakeState> moodShakeKey;
  final GlobalKey<ShakeState> durationShakeKey;
  final GlobalKey<ShakeState> activityShakeKey;
  final bool showHint;
  final ValueChanged<Mood> onDeclare;

  /// The answer decides whether the paint stays off or is restored on failure.
  final Future<bool> Function() onEnd;
  final VoidCallback onChangeMood;
  final ValueChanged<int> onSelectDuration;
  final ValueChanged<Activity?> onSelectActivity;
  final VoidCallback onExpired;

  @override
  MyStatusHeroState createState() => MyStatusHeroState();
}

class MyStatusHeroState extends State<MyStatusHero>
    with TickerProviderStateMixin {
  static const _wipeDuration = Duration(milliseconds: 560);
  static const _wipeHold = 0.88;
  static const _wipeFinishDuration = Duration(milliseconds: 140);
  static const _restoreDuration = Duration(milliseconds: 260);

  late final AnimationController _burst;
  late final AnimationController _wipe;

  bool _bursting = false;
  bool _ending = false;
  HeroState? _endingState;
  HeroInlinePicker? _picker;
  HeroInlinePicker? _pendingDemoPicker;
  Offset? _pickerOriginGlobal;

  @override
  void initState() {
    super.initState();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _wipe = AnimationController(vsync: this, duration: _wipeDuration);
  }

  @override
  void didUpdateWidget(MyStatusHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy && !widget.busy) _openPendingDemoPicker();
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

  /// Demo panel requests enter the same inline picker as the hero controls.
  bool openInlinePicker(HeroInlinePicker picker) {
    if (!mounted) return false;
    if (widget.busy || _ending) {
      _pendingDemoPicker = picker;
      return true;
    }
    _openPicker(picker, null);
    return true;
  }

  void _openPendingDemoPicker() {
    final picker = _pendingDemoPicker;
    if (picker == null || widget.busy || _ending) return;
    _pendingDemoPicker = null;
    _openPicker(picker, null);
  }

  void _openPicker(HeroInlinePicker picker, Offset? originGlobal) {
    if (widget.busy || _ending) return;
    setState(() {
      _picker = picker;
      _pickerOriginGlobal = originGlobal == Offset.zero ? null : originGlobal;
    });
  }

  void _closePicker() {
    if (_picker == null) return;
    setState(() {
      _picker = null;
      _pickerOriginGlobal = null;
    });
  }

  void _chooseActivity(ActivityChoice choice) {
    _closePicker();
    widget.onSelectActivity(choice.activity);
  }

  int get _durationValue => widget.state.isDeclared
      ? widget.state.durationMin
      : widget.selectedDurationMin;

  void _commitDuration(int minutes) {
    _closePicker();
    if (minutes != _durationValue) widget.onSelectDuration(minutes);
  }

  void _stepDuration(int direction) {
    final currentIndex = himaDurationChoices.indexOf(_durationValue);
    final index = (currentIndex + direction)
        .clamp(0, himaDurationChoices.length - 1)
        .toInt();
    if (index == currentIndex) return;
    AppHaptics.select();
    widget.onSelectDuration(himaDurationChoices[index]);
  }

  /// The brush stops one strip short while the request is in flight. A failed
  /// end paints the same declaration back without flashing the OFF state.
  Future<void> _handleEnd() async {
    if (_ending || widget.busy || !widget.state.isDeclared) return;
    if (MediaQuery.disableAnimationsOf(context)) {
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
      _openPendingDemoPicker();
      return;
    }
    await _wipe.animateBack(
      0,
      duration: _restoreDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() => _ending = false);
    _endingState = null;
    _openPendingDemoPicker();
  }

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
    return PopScope<Object?>(
      canPop: _picker == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closePicker();
      },
      child: TapRegion(
        onTapOutside: _picker == null ? null : (_) => _closePicker(),
        child: AnimatedSize(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            // Keep a short fade for reduced motion; disable the size animation.
            duration: reduceMotion
                ? const Duration(milliseconds: 100)
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: _picker == null
                ? _normalContent(
                    key: ValueKey(
                      reduceMotion
                          ? 'hero-content-${widget.state.isDeclared}'
                          : 'hero-content',
                    ),
                  )
                : _inlinePicker(key: ValueKey(_picker)),
          ),
        ),
      ),
    );
  }

  Widget _inlinePicker({required Key key}) {
    if (_picker == HeroInlinePicker.activity) {
      return InlineActivityPicker(
        key: key,
        current: widget.selectedActivity,
        originGlobal: _pickerOriginGlobal,
        onSelected: _chooseActivity,
        onClose: _closePicker,
      );
    }
    return InlineDurationPicker(
      key: key,
      current: _durationValue,
      onCommit: _commitDuration,
      onClose: _closePicker,
    );
  }

  Widget _normalContent({required Key key}) {
    final state = widget.state;
    final declared = state.isDeclared;
    final onState = _ending ? (_endingState ?? state) : state;
    final showPaint = declared || _ending;
    final showPaper = !declared || _ending;

    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topLeft,
            children: [
              if (showPaint)
                const Positioned.fill(
                  key: ValueKey('paper-paint'),
                  child: HeroIdlePaint(),
                ),
              if (showPaper) _paperLayer(state),
              if (showPaint)
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
                          ),
                        ),
                        _declaredLayer(onState, front),
                        if (!_ending) _declaredSparkles(),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        if (!declared && !_ending) ...[
          const SizedBox(height: AppSpacing.s8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Shake(
              key: widget.activityShakeKey,
              child: ActivityChips(
                selected: widget.selectedActivity,
                onSelected: widget.onSelectActivity,
                onOpenPicker: (origin) =>
                    _openPicker(HeroInlinePicker.activity, origin),
              ),
            ),
          ),
        ],
      ],
    );
  }

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
        child: Padding(padding: heroBlobPadding, child: _onContent(state)),
      ),
    );
    if (wipe <= 0) return content;
    return ClipPath(
      clipper: _WipeClipper(progress: wipe, seed: heroBlobSeed),
      child: content,
    );
  }

  Widget _heroHeading(
    BuildContext context,
    HeroState state,
    TextStyle style, {
    required double size,
    Alignment alignment = Alignment.centerLeft,
  }) {
    final requested = MediaQuery.textScalerOf(context).scale(size);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final maxFontSize = textScale > 1.25 ? size : size + 8;
    final fontSize = requested.clamp(size, maxFontSize).toDouble();
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(
          state.heading,
          maxLines: 1,
          softWrap: false,
          style: style.copyWith(fontSize: fontSize),
        ),
      ),
    );
  }

  Widget _offContent(HeroState state) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MediaQuery(
            // The avatar stays fixed-size; its decorative initial must fit too.
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: AvatarView(
              name: widget.me.displayName,
              imageUrl: widget.me.avatarUrl,
              size: 56,
              background: AppColors.surface,
              ring: AppColors.surface,
              ringWidth: 2,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _heroHeading(
                  context,
                  state,
                  AppTextStyles.heroTitle.copyWith(color: AppColors.ink),
                  size: 38,
                ),
                const SizedBox(height: 2),
                Text(
                  state.supporting,
                  semanticsLabel: plainPhrases(state.supporting),
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.s12),
      Center(
        child: FractionallySizedBox(
          widthFactor: MediaQuery.textScalerOf(context).scale(18) / 18 > 1.4
              ? 0.94
              : 0.68,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: PaintDab(
              seed: 4242,
              color: AppColors.yellow,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s12,
              ),
              wobble: 0.1,
              droplets: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.ink,
                      ),
                    )
                  else
                    const Icon(
                      Icons.campaign_rounded,
                      size: 23,
                      color: AppColors.ink,
                    ),
                  const SizedBox(width: AppSpacing.s8),
                  Flexible(
                    child: Text(
                      'ひまを宣言',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.button.copyWith(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (widget.showHint) ...[
        const SizedBox(height: AppSpacing.s8),
        Text(
          '長押しで温度感を選べるよ',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.ink.withValues(alpha: 0.78),
          ),
        ),
      ],
    ],
  );

  Widget _onContent(HeroState state) {
    final textScale = MediaQuery.textScalerOf(context).scale(20) / 20;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                _heroHeading(
                  context,
                  state,
                  AppTextStyles.heroTitle.copyWith(
                    color: AppColors.surface,
                    shadows: const [
                      Shadow(
                        color: Color(0x442F124F),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  size: 42,
                  alignment: Alignment.center,
                ),
                const SizedBox(height: AppSpacing.s4),
                const Center(
                  child: BrushStroke(
                    seed: 23,
                    size: Size(156, 10),
                    color: AppColors.yellow,
                  ),
                ),
              ],
            ),
            Positioned(
              left: -34,
              top: -16,
              child: _MoodAvatar(
                mood: state.mood,
                me: widget.me,
                shakeKey: widget.moodShakeKey,
                onTap: widget.onChangeMood,
              ),
            ),
            Positioned(
              top: 0,
              right: 4,
              child: IgnorePointer(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.rotate(
                      angle: -0.55,
                      child: const BrushStroke(
                        seed: 31,
                        size: Size(7, 17),
                        color: AppColors.yellow,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Transform.rotate(
                      angle: 0.25,
                      child: const BrushStroke(
                        seed: 32,
                        size: Size(8, 22),
                        color: AppColors.yellow,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Transform.rotate(
                      angle: 0.7,
                      child: const BrushStroke(
                        seed: 33,
                        size: Size(7, 15),
                        color: AppColors.yellow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 280 || textScale > 1.25;
            final duration = Shake(
              key: widget.durationShakeKey,
              child: _RemainingPill(
                expiresAt: state.expiresAt!,
                onTap: (origin) =>
                    _openPicker(HeroInlinePicker.duration, origin),
                onStep: _stepDuration,
                onExpired: widget.onExpired,
              ),
            );
            final activity = Shake(
              key: widget.activityShakeKey,
              child: _ActivityPill(
                activity: state.activity,
                onTap: (origin) =>
                    _openPicker(HeroInlinePicker.activity, origin),
              ),
            );
            if (stacked) {
              return Column(
                children: [
                  duration,
                  const SizedBox(height: AppSpacing.s8),
                  activity,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: duration),
                const SizedBox(width: AppSpacing.s8),
                Expanded(child: activity),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.s12),
        Center(
          child: FractionallySizedBox(
            widthFactor: textScale > 1.4 ? 0.94 : 0.64,
            child: _EndPaintButton(
              onTap: () => unawaited(_handleEnd()),
              enabled: !_ending && !widget.busy,
            ),
          ),
        ),
      ],
    );
  }

  Widget _declaredSparkles() => Positioned.fill(
    child: IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 4,
            top: 2,
            child: PaintMark(
              kind: PaintMarkKind.star,
              seed: 41,
              color: AppColors.yellow,
              size: 22,
            ),
          ),
          Positioned(
            left: 0,
            bottom: 8,
            child: PaintMark(
              kind: PaintMarkKind.star,
              seed: 42,
              color: AppColors.yellow,
              size: 16,
            ),
          ),
        ],
      ),
    ),
  );
}

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
          MediaQuery(
            // The avatar stays fixed-size; its decorative initial must fit too.
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: AvatarView(
              name: me.displayName,
              imageUrl: me.avatarUrl,
              size: 56,
              background: AppColors.surface,
              ring: AppColors.surface,
              ringWidth: 2,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            child: Semantics(
              button: true,
              label: '温度感を変更',
              hint: mood.label,
              onTap: onTap,
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Padding(
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

class _HeroPillSurface extends StatelessWidget {
  const _HeroPillSurface({required this.child, required this.seed});

  final Widget child;
  final int seed;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 60),
    child: PaintThick(
      seed: seed,
      colors: const [Color(0xFFFFF9FC), Color(0xFFFFEAF3)],
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 13),
      wobble: 0.07,
      droplets: 1,
      drips: 0,
      arms: 1,
      armLength: 0.015,
      gloss: 0.65,
      bristles: false,
      dryEdge: false,
      child: child,
    ),
  );
}

class _RemainingPill extends StatefulWidget {
  const _RemainingPill({
    required this.expiresAt,
    required this.onTap,
    required this.onStep,
    required this.onExpired,
  });

  final DateTime expiresAt;
  final ValueChanged<Offset> onTap;
  final ValueChanged<int> onStep;
  final VoidCallback onExpired;

  @override
  State<_RemainingPill> createState() => _RemainingPillState();
}

class _RemainingPillState extends State<_RemainingPill> {
  Timer? _timer;
  bool _reportedExpiry = false;
  Offset _tapOrigin = Offset.zero;
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (widget.expiresAt.difference(DateTime.now().toUtc()) <=
              Duration.zero &&
          !_reportedExpiry) {
        _reportedExpiry = true;
        widget.onExpired();
      }
    });
  }

  @override
  void didUpdateWidget(_RemainingPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expiresAt != oldWidget.expiresAt) _reportedExpiry = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _stepFromDrag() {
    if (_dragDistance.abs() < 24) return;
    widget.onStep(_dragDistance > 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final label = himaRemainingShortLabel(widget.expiresAt);
    return Semantics(
      button: true,
      label: 'ひまの長さ、$label',
      hint: 'タップで変更。左右にスワイプで長さを変更',
      onTap: () => widget.onTap(_tapOrigin),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _tapOrigin = details.globalPosition,
        onTap: () => widget.onTap(_tapOrigin),
        onHorizontalDragStart: (details) {
          _tapOrigin = details.globalPosition;
          _dragDistance = 0;
        },
        onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
        onHorizontalDragEnd: (details) {
          if (_dragDistance.abs() < 24 &&
              (details.primaryVelocity ?? 0).abs() > 300) {
            _dragDistance = details.primaryVelocity!;
          }
          _stepFromDrag();
        },
        child: _HeroPillSurface(
          seed: 61,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 21,
                color: AppColors.ink,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 20,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.activity, required this.onTap});

  final Activity? activity;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    final style = activity == null ? null : ActivityStyle.of(activity!);
    var origin = Offset.zero;
    final label = activity?.label ?? 'なにする？';
    return Semantics(
      button: true,
      label: activity == null ? 'なにする？' : '活動、$label',
      hint: '活動を選ぶ',
      onTap: () => onTap(origin),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => origin = details.globalPosition,
        onTap: () => onTap(origin),
        child: _HeroPillSurface(
          seed: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                style?.icon ?? Icons.add_rounded,
                size: 21,
                color: style?.accent ?? AppColors.ink,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 20,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.expand_more_rounded,
                size: 19,
                color: AppColors.ink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndPaintButton extends StatelessWidget {
  const _EndPaintButton({required this.onTap, required this.enabled});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'おわる',
    onTap: enabled ? onTap : null,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: PaintThick(
          seed: 6401,
          colors: const [Color(0xFFFFB9DA), Color(0xFFFF9ECB)],
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          wobble: 0.09,
          droplets: 3,
          drips: 0,
          arms: 2,
          armLength: 0.02,
          gloss: 0.85,
          bristles: false,
          dryEdge: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_rounded, size: 30, color: AppColors.ink),
              const SizedBox(width: AppSpacing.s8),
              Text(
                'おわる',
                style: AppTextStyles.button.copyWith(
                  fontSize: 24,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
