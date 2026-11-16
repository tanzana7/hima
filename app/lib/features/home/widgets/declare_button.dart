import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import 'pickers.dart';

/// The yellow 「ひまを宣言」 pill.
///
/// Tap declares immediately with the last used mood (Design.md: the first
/// declaration must not require answering a question). Long-press opens the
/// mood bubbles around the finger; releasing on one declares with it, releasing
/// anywhere else cancels.
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
  static const _buttonHeight = 60.0;
  static const _bubbleSize = 68.0;
  static const _arcRadius = 104.0;

  late final AnimationController _menuController;
  late final AnimationController _commitController;
  late final AnimationController _pressController;
  late final AnimationController _shakeController;

  bool _menuOpen = false;
  Offset _origin = Offset.zero;
  Mood? _hovered;
  Mood? _committing;
  Size _stackSize = Size.zero;

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
    setState(() {
      _menuOpen = true;
      _origin = details.localPosition;
      _hovered = null;
      _committing = null;
    });
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
    _menuController.value = 0;
    _commitController.value = 0;
    widget.onDeclare(mood);
  }

  void _cancelMenu() {
    AppHaptics.cancel();
    if (_reduceMotion) {
      setState(() {
        _menuOpen = false;
        _hovered = null;
      });
      _menuController.value = 0;
      return;
    }
    _menuController.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _menuOpen = false;
        _hovered = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    // At very large text sizes the bubbles drop their labels instead of
    // growing past the hero; the emoji and the screen reader label stay.
    final showLabels = textScale <= 1.3;
    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, _buttonHeight);
        return SizedBox(
          height: _buttonHeight,
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
              if (_menuOpen)
                for (var index = 0; index < Mood.values.length; index++)
                  _bubble(context, Mood.values[index], index, showLabels),
            ],
          ),
        );
      },
    );
  }

  Widget _buttonVisual(BuildContext context) => Container(
    height: _buttonHeight,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
    decoration: BoxDecoration(
      color: AppColors.yellow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      boxShadow: [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
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

  Widget _bubble(
    BuildContext context,
    Mood mood,
    int index,
    bool showLabels,
  ) {
    final center = _bubbleCenter(index);
    final isHovered = _hovered == mood;
    final isCommitting = _committing == mood;
    final start = 0.05 * index;
    final pop = CurvedAnimation(
      parent: _menuController,
      curve: Interval(start, start + 0.6, curve: Curves.elasticOut),
    );
    final hoverScale = isHovered ? 1.3 : (_hovered == null ? 1.0 : 0.9);
    final buttonCenter = Offset(_stackSize.width / 2, _buttonHeight / 2);

    return Positioned(
      left: center.dx - _bubbleSize / 2,
      top: center.dy - _bubbleSize / 2,
      width: _bubbleSize,
      height: _bubbleSize,
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
        child: AnimatedScale(
          scale: hoverScale,
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          // Kept out of the accessibility tree: a bubble is a touch affordance
          // that only exists mid-long-press, so a focusable button here would be
          // a dead end. The declare button exposes the same choice as a custom
          // action instead.
          child: ExcludeSemantics(
            child: Container(
              decoration: BoxDecoration(
                color: _moodTint(mood),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.ink,
                  width: AppSpacing.borderWidth,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(mood.emoji, style: const TextStyle(fontSize: 24)),
                  if (showLabels)
                    Text(
                      _shortLabel(mood),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
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
