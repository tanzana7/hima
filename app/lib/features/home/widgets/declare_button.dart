import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/paint/paint.dart';
import 'pickers.dart';

/// The yellow 「ひまを宣言」 paint dab.
///
/// Tap declares immediately with the last used mood (Design.md: the first
/// declaration must not require answering a question). Long-press opens the
/// mood bubbles around the finger; releasing on one declares with it, releasing
/// anywhere else cancels.
///
/// The bubbles and their scrim live in the root [Overlay], not in the hero: the
/// bubbles arc above the button over the heading, and a scrim drawn inside the
/// list would be painted over by the cards below it. The scrim is punched out
/// around the button so the button and the bubbles stay the only bright things
/// while the rest of the screen dims.
class DeclareButton extends StatefulWidget {
  const DeclareButton({
    super.key,
    required this.lastMood,
    required this.busy,
    required this.shakeToken,
    required this.onDeclare,
  });

  final Mood lastMood;
  final bool busy;

  /// Incremented by the parent when a declaration failed, so the control can
  /// shake without the parent knowing its internals.
  final int shakeToken;

  final ValueChanged<Mood> onDeclare;

  @override
  State<DeclareButton> createState() => DeclareButtonState();
}

class DeclareButtonState extends State<DeclareButton>
    with TickerProviderStateMixin {
  /// Height of the button at the default text scale.
  static const _minButtonHeight = 60.0;

  /// Room the dab keeps above and below its label. The button height is derived
  /// from it, so the two cannot drift apart.
  static const _dabPaddingV = 10.0;

  static const _bubbleSize = 68.0;
  static const _arcRadius = 104.0;

  /// Width of the box a bubble is positioned in: the circle plus room for the
  /// label underneath it. Wide enough for the longest label at 200% text.
  static const _bubbleSlotWidth = 120.0;

  late final AnimationController _menuController;
  late final AnimationController _commitController;
  late final AnimationController _pressController;
  late final AnimationController _shakeController;

  bool _menuOpen = false;
  Offset _origin = Offset.zero;
  Mood? _hovered;
  Mood? _committing;
  Size _stackSize = Size.zero;

  /// Global rect of the button, captured when the menu opens. It anchors the
  /// bubbles and the hole in the scrim.
  Rect _buttonRect = Rect.zero;

  OverlayEntry? _scrimEntry;
  OverlayEntry? _bubbleEntry;

  @override
  void initState() {
    super.initState();
    // Eager: lazy `late` fields would otherwise be built from dispose() when
    // the menu never opened, which is not a safe time to create a Ticker.
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _commitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didUpdateWidget(DeclareButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shakeToken != oldWidget.shakeToken) {
      if (!MediaQuery.disableAnimationsOf(context)) {
        _shakeController.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _removeMenuOverlay();
    _menuController.dispose();
    _commitController.dispose();
    _pressController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  double get _pressScale {
    final t = _pressController.value;
    if (_pressController.status == AnimationStatus.reverse) {
      // Spring back with a small overshoot so the tap feels physical.
      final spring = Curves.elasticOut.transform(1 - t);
      return 0.92 + 0.08 * spring;
    }
    return 1 - 0.08 * Curves.easeOutCubic.transform(t);
  }

  Offset _bubbleCenter(int index) {
    // 205° / 270° / 335°: an arc that opens upward around the finger.
    final angle = math.pi * (1.14 + 0.36 * index);
    final raw = _origin + Offset(math.cos(angle), math.sin(angle)) * _arcRadius;
    // Keep every bubble on screen so a press near an edge cannot make a mood
    // unreachable.
    final minX = _bubbleSize / 2 + 2;
    final maxX = _stackSize.width - _bubbleSize / 2 - 2;
    final x = maxX <= minX
        ? _stackSize.width / 2
        : raw.dx.clamp(minX, maxX).toDouble();
    return Offset(x, raw.dy);
  }

  Mood? _moodAt(Offset localPosition) {
    for (var index = 0; index < Mood.values.length; index++) {
      final distance = (localPosition - _bubbleCenter(index)).distance;
      if (distance <= _bubbleSize * 0.72) return Mood.values[index];
    }
    return null;
  }

  void _handleTap() {
    if (widget.busy) return;
    widget.onDeclare(widget.lastMood);
  }

  /// The squash-and-spring is decoration, so reduced motion drops it; the tap
  /// itself stays because declaring is the primary action of the screen.
  void _pressIn() {
    if (_reduceMotion) return;
    _pressController.forward();
  }

  void _pressOut() {
    if (_reduceMotion) return;
    _pressController.reverse();
  }

  /// The bubbles only exist while a finger holds the button, which a screen
  /// reader cannot do, so the same three choices are offered as an explicit
  /// action that opens an operable picker.
  Future<void> _pickMood() async {
    if (widget.busy) return;
    final mood = await showMoodPicker(context, current: widget.lastMood);
    if (mood == null || !mounted) return;
    widget.onDeclare(mood);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (widget.busy) return;
    AppHaptics.openMenu();
    final box = context.findRenderObject();
    final origin = box is RenderBox
        ? box.localToGlobal(Offset.zero)
        : Offset.zero;
    setState(() {
      _menuOpen = true;
      _origin = details.localPosition;
      _hovered = null;
      _committing = null;
      _buttonRect = origin & (box is RenderBox ? box.size : _stackSize);
    });
    _insertMenuOverlay();
    if (_reduceMotion) {
      _menuController.value = 1;
    } else {
      _menuController.forward(from: 0);
    }
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_menuOpen || _committing != null) return;
    final mood = _moodAt(details.localPosition);
    if (mood == _hovered) return;
    setState(() => _hovered = mood);
    _refreshMenuOverlay();
    if (mood != null) AppHaptics.select();
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    final mood = _hovered;
    if (mood == null) {
      _cancelMenu();
      return;
    }
    // No haptic here: the single heavy impact belongs to the successful
    // declaration, so a failed request must not feel like a success.
    setState(() => _committing = mood);
    _refreshMenuOverlay();
    if (_reduceMotion) {
      _finishCommit(mood);
      return;
    }
    _commitController.forward(from: 0).whenComplete(() => _finishCommit(mood));
  }

  void _finishCommit(Mood mood) {
    if (!mounted) return;
    setState(() {
      _menuOpen = false;
      _hovered = null;
      _committing = null;
    });
    _commitController.value = 0;
    if (_reduceMotion) {
      _menuController.value = 0;
      _removeMenuOverlay();
      widget.onDeclare(mood);
      return;
    }
    // Fade the scrim out and only then drop the overlay: removing it straight
    // away made the screen snap back to full brightness the moment a mood was
    // chosen. The declaration waits for the fade, because a rebuild would
    // dispose this button (and its overlay) mid-fade.
    _menuController
        .animateBack(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (!mounted) return;
          _removeMenuOverlay();
          widget.onDeclare(mood);
        });
  }

  void _cancelMenu() {
    AppHaptics.cancel();
    if (_reduceMotion) {
      setState(() {
        _menuOpen = false;
        _hovered = null;
      });
      _menuController.value = 0;
      _removeMenuOverlay();
      return;
    }
    _menuController.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _menuOpen = false;
        _hovered = null;
      });
      _removeMenuOverlay();
    });
  }

  void _insertMenuOverlay() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _scrimEntry = OverlayEntry(builder: _buildScrim);
    _bubbleEntry = OverlayEntry(builder: _buildBubbles);
    // Inserted in order so the bubbles stay above the scrim.
    overlay.insertAll([_scrimEntry!, _bubbleEntry!]);
  }

  void _removeMenuOverlay() {
    _scrimEntry?.remove();
    _bubbleEntry?.remove();
    _scrimEntry = null;
    _bubbleEntry = null;
  }

  /// The entries are separate widgets, so a hover change has to be pushed to
  /// them explicitly.
  void _refreshMenuOverlay() {
    _scrimEntry?.markNeedsBuild();
    _bubbleEntry?.markNeedsBuild();
  }

  Widget _buildScrim(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _menuController,
      builder: (context, _) => CustomPaint(
        painter: _ScrimPainter(
          hole: _buttonRect.inflate(2),
          opacity: 0.35 * _menuController.value.clamp(0.0, 1.0),
        ),
      ),
    ),
  );

  Widget _buildBubbles(BuildContext context) => Material(
    // The menu lives in the root Overlay, outside any Scaffold, so it needs its
    // own Material: without one the labels fall back to the framework's
    // placeholder text style (yellow underline).
    type: MaterialType.transparency,
    child: IgnorePointer(
      child: Stack(
        children: [
          for (var index = 0; index < Mood.values.length; index++)
            _bubble(context, Mood.values[index], index),
        ],
      ),
    ),
  );

  /// The button height follows the text scale.
  ///
  /// A fixed 60dp box left only 40dp for the label once the dab's padding was
  /// taken out, and a 19sp label at 200% needs 45.6dp, so it clipped. Growing
  /// with the label keeps the CTA inside the hero at every scale.
  double _buttonHeightFor(BuildContext context) {
    final style = AppTextStyles.button;
    final label =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 19) *
        (style.height ?? 1.2);
    return math.max(_minButtonHeight, label + _dabPaddingV * 2 + 2);
  }

  @override
  Widget build(BuildContext context) {
    final buttonHeight = _buttonHeightFor(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, buttonHeight);
        return SizedBox(
          height: buttonHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: widget.busy ? null : (_) => _pressIn(),
                  onTapUp: widget.busy ? null : (_) => _pressOut(),
                  onTapCancel: widget.busy ? null : _pressOut,
                  onTap: widget.busy ? null : _handleTap,
                  onLongPressStart: _handleLongPressStart,
                  onLongPressMoveUpdate: _handleLongPressMove,
                  onLongPressEnd: _handleLongPressEnd,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _pressController,
                      _shakeController,
                    ]),
                    builder: (context, child) {
                      final shake = _shakeController.isAnimating
                          ? math.sin(_shakeController.value * math.pi * 6) *
                                9 *
                                (1 - _shakeController.value)
                          : 0.0;
                      return Transform.translate(
                        offset: Offset(shake, 0),
                        child: Transform.scale(
                          scale: _pressScale,
                          child: child,
                        ),
                      );
                    },
                    child: Semantics(
                      button: true,
                      label: 'ひまを宣言',
                      hint: '温度感を選んで宣言できます',
                      customSemanticsActions: {
                        const CustomSemanticsAction(label: '温度感を選んで宣言'):
                            _pickMood,
                      },
                      excludeSemantics: true,
                      child: _buttonVisual(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The main CTA is a paint dab, not a stadium: a perfect pill was the
  /// straightest thing left on the home screen. The padding matches
  /// [_dabPaddingV] so the label always has room inside the paint.
  Widget _buttonVisual(BuildContext context) => PaintDab(
    seed: 4242,
    color: AppColors.yellow,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s24,
      vertical: _dabPaddingV,
    ),
    wobble: 0.028,
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
            color: AppColors.ink,
            size: 24,
          ),
        const SizedBox(width: AppSpacing.s8),
        Flexible(
          child: Text(
            'ひまを宣言',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.button,
          ),
        ),
      ],
    ),
  );

  Widget _bubble(BuildContext context, Mood mood, int index) {
    final center = _buttonRect.topLeft + _bubbleCenter(index);
    final isHovered = _hovered == mood;
    final isCommitting = _committing == mood;
    final start = 0.05 * index;
    final pop = CurvedAnimation(
      parent: _menuController,
      curve: Interval(start, start + 0.6, curve: Curves.elasticOut),
    );
    final hoverScale = isHovered ? 1.3 : (_hovered == null ? 1.0 : 0.9);
    final buttonCenter =
        _buttonRect.topLeft + Offset(_buttonRect.width / 2, _buttonRect.height / 2);

    return Positioned(
      left: center.dx - _bubbleSlotWidth / 2,
      top: center.dy - _bubbleSize / 2,
      width: _bubbleSlotWidth,
      child: AnimatedBuilder(
        animation: Listenable.merge([_menuController, _commitController]),
        builder: (context, child) {
          var scale = _reduceMotion ? 1.0 : pop.value.clamp(0.0, 1.4);
          var offset = Offset.zero;
          if (isCommitting) {
            final t = _reduceMotion ? 1.0 : _commitController.value;
            scale *= 1 - t * 0.85;
            offset = (buttonCenter - center) * t;
          }
          return Transform.translate(
            offset: offset,
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: hoverScale,
              duration: _reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOutBack,
              // Kept out of the accessibility tree: a bubble is a touch
              // affordance that only exists mid-long-press, so a focusable
              // button here would be a dead end. The declare button exposes the
              // same choice as a custom action instead.
              // A paint dab rather than a bordered circle: the mood bubbles
              // are thrown at the paper too, and the ink stroke that used to
              // outline them was the last hairline on the home screen.
              child: ExcludeSemantics(
                child: PaintDab(
                  seed: 7000 + index,
                  color: _moodTint(mood),
                  padding: const EdgeInsets.all(10),
                  wobble: 0.05,
                  droplets: 2,
                  child: SizedBox(
                    width: _bubbleSize - 20,
                    height: _bubbleSize - 20,
                    child: Center(
                      child: Text(
                        mood.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            // Below the circle on a solid chip: the label used to sit inside the
            // bubble over the heading and was hard to read. It stays visible at
            // every text scale and wraps instead of being dropped.
            ExcludeSemantics(
              child: PaintDab(
                seed: 7100 + index,
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                wobble: 0.05,
                child: Text(
                  _shortLabel(mood),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _moodTint(Mood mood) => switch (mood) {
    Mood.fire => AppColors.peachSoft,
    Mood.ok => AppColors.purpleSoft,
    Mood.quiet => AppColors.skySoft,
  };

  static String _shortLabel(Mood mood) => switch (mood) {
    Mood.fire => '今すぐ',
    Mood.ok => '誘われたら',
    Mood.quiet => 'ひっそり',
  };
}

/// Dims the screen except for the button, so the bubbles no longer sit on top of
/// the readable heading.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.opacity});

  final Rect hole;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final full = Path()..addRect(Offset.zero & size);
    final cut = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          hole,
          const Radius.circular(AppSpacing.radiusPill),
        ),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, cut),
      Paint()..color = AppColors.ink.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.hole != hole;
}
