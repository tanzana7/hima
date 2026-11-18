import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A scatter of paint drops thrown in one direction.
///
/// It replaces the `///` sparkle strokes: the same "something happened here"
/// punctuation, drawn as thrown paint. The drops are seeded, so the scatter is
/// identical on every rebuild, and they are decoration, so they stay out of the
/// semantics tree and ignore pointers.
///
/// The drops are deliberately not an even sprinkle. They leave one point in a
/// seeded direction, get smaller as they travel and keep a little lateral
/// spread, which is what makes the group read as one splash rather than as
/// background noise. A single dot of the same size at random positions reads as
/// noise however many of them there are.
class SplatterDots extends StatelessWidget {
  const SplatterDots({
    super.key,
    required this.seed,
    required this.color,
    this.size = const Size(30, 24),
    this.count = 7,
  });

  final int seed;
  final Color color;
  final Size size;

  /// 4–10. More reads as noise rather than as a flick of paint.
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
    // One seeded direction for the whole group: every drop leaves the same
    // point, so the scatter has a source instead of a uniform sprinkle.
    final angle = rng.nextDouble() * math.pi * 2;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-direction.dy, direction.dx);
    final origin =
        Offset(size.width / 2, size.height / 2) - direction * (scale * 0.5);

    for (var i = 0; i < count; i++) {
      final t = (i + 1) / count;
      final travel =
          scale * (0.45 + 0.95 * t) * (0.82 + 0.36 * rng.nextDouble());
      // The spread widens with distance, the way a splash fans out.
      final lateral =
          (rng.nextDouble() - 0.5) * scale * 0.6 * (0.35 + t);
      // The first drops are the fat ones; the far ones are specks.
      final radius =
          (scale * (0.115 - 0.075 * t) * (0.75 + 0.5 * rng.nextDouble())).clamp(
            1.0,
            5.0,
          );
      canvas.drawCircle(
        origin + direction * travel + normal * lateral,
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SplatterDotsPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.color != color ||
      oldDelegate.count != count;
}
