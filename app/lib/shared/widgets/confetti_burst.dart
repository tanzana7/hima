import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A one-shot confetti burst used when a knock is answered with 「いいよ！」.
///
/// It paints once and then reports completion so the parent can drop it from
/// the tree; there is no looping sparkle anywhere in the app.
///
/// Pieces leave from the middle of the surface and from both bottom corners,
/// and travel far enough to reach the screen edges, so the celebration reads as
/// full-screen instead of as a puff around whatever card is in the middle.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.onCompleted, this.particleCount = 46});

  final VoidCallback? onCompleted;
  final int particleCount;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduced motion: no burst at all, just tell the parent it is done.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      _controller.forward();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(
              progress: _controller.value,
              particleCount: widget.particleCount,
            ),
          ),
        ),
      ),
    );
  }
}

/// One launch point, expressed as a fraction of the surface plus the direction
/// the pieces fan out in and how far they travel relative to the longest side.
class _Emitter {
  const _Emitter({
    required this.dx,
    required this.dy,
    required this.angle,
    required this.spread,
    required this.reach,
  });

  final double dx;
  final double dy;
  final double angle;
  final double spread;
  final double reach;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.particleCount});

  final double progress;
  final int particleCount;

  static const _colors = [
    AppColors.coral,
    AppColors.yellow,
    AppColors.lime,
    AppColors.purple,
    AppColors.skySoft,
  ];

  /// A centre burst plus two corner cannons firing up and inward. Together they
  /// put pieces in every part of the screen, not just around the card.
  static const _emitters = [
    _Emitter(
      dx: 0.5,
      dy: 0.42,
      angle: 0,
      spread: math.pi * 2,
      reach: 0.62,
    ),
    _Emitter(
      dx: -0.02,
      dy: 1.02,
      angle: -math.pi / 4,
      spread: math.pi / 5,
      reach: 0.95,
    ),
    _Emitter(
      dx: 1.02,
      dy: 1.02,
      angle: -math.pi * 3 / 4,
      spread: math.pi / 5,
      reach: 0.95,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final random = math.Random(7);
    final span = size.longestSide;
    final fade = progress < 0.72
        ? 1.0
        : (1 - (progress - 0.72) / 0.28).clamp(0.0, 1.0).toDouble();
    for (var i = 0; i < particleCount; i++) {
      final emitter = _emitters[i % _emitters.length];
      final origin = Offset(size.width * emitter.dx, size.height * emitter.dy);
      final angle =
          emitter.angle + (random.nextDouble() - 0.5) * emitter.spread;
      final speed = span * emitter.reach * (0.45 + random.nextDouble() * 0.55);
      final spin = random.nextDouble() * math.pi;
      final particleSize = 5 + random.nextDouble() * 5;
      final color = _colors[i % _colors.length];
      final distance = speed * progress;
      final position =
          origin +
          Offset(math.cos(angle), math.sin(angle)) * distance +
          Offset(0, span * 0.16 * progress * progress);
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(spin + progress * math.pi);
      final paint = Paint()..color = color.withValues(alpha: fade);
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: particleSize,
            height: particleSize * 0.6,
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, particleSize / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
