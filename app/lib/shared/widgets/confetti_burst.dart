import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A one-shot confetti burst used when a knock is answered with 「いいよ！」.
///
/// It paints once and then reports completion so the parent can drop it from
/// the tree; there is no looping sparkle anywhere in the app.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.onCompleted, this.particleCount = 18});

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
      duration: const Duration(milliseconds: 900),
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

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final random = math.Random(7);
    final origin = Offset(size.width / 2, size.height * 0.45);
    final fade = progress < 0.7 ? 1.0 : (1 - (progress - 0.7) / 0.3);
    for (var i = 0; i < particleCount; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final speed = 40 + random.nextDouble() * 90;
      final spin = random.nextDouble() * math.pi;
      final particleSize = 4 + random.nextDouble() * 5;
      final color = _colors[i % _colors.length];
      final distance = speed * progress;
      final position =
          origin +
          Offset(math.cos(angle), math.sin(angle)) * distance +
          Offset(0, 60 * progress * progress);
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
