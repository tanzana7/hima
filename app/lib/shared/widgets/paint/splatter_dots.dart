import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A scatter of small paint drops.
///
/// It replaces the `///` sparkle strokes: the same "something happened here"
/// punctuation, drawn as thrown paint. The drops are seeded, so the scatter is
/// identical on every rebuild, and they are decoration, so they stay out of the
/// semantics tree and ignore pointers.
class SplatterDots extends StatelessWidget {
  const SplatterDots({
    super.key,
    required this.seed,
    required this.color,
    this.size = const Size(30, 24),
    this.count = 6,
  });

  final int seed;
  final Color color;
  final Size size;

  /// 4–8. More reads as noise rather than as a flick of paint.
  final int count;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: _SplatterDotsPainter(seed: seed, color: color, count: count),
        ),
      ),
    ),
  );
}

class _SplatterDotsPainter extends CustomPainter {
  const _SplatterDotsPainter({
    required this.seed,
    required this.color,
    required this.count,
  });

  final int seed;
  final Color color;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rng = math.Random(seed);
    final paint = Paint()..color = color;
    final scale = size.shortestSide;
    for (var i = 0; i < count; i++) {
      // Biased toward one corner so the scatter has a direction, the way a
      // flick of the brush throws paint.
      final t = i / math.max(1, count - 1);
      final x = size.width * (0.12 + 0.82 * rng.nextDouble());
      final y = size.height * (0.12 + 0.82 * rng.nextDouble());
      final radius = scale * (0.05 + 0.11 * rng.nextDouble()) * (1 - t * 0.45);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SplatterDotsPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.color != color ||
      oldDelegate.count != count;
}
