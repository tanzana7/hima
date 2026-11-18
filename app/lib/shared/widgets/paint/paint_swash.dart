import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// A wide, shallow wash that spans the full width and runs off the bottom of
/// the box, so only its top edge is visible.
///
/// That edge is a seeded wobble rather than a straight line. Two or three
/// overlapping layers give it watercolour depth, and a faint pooling line
/// follows the top edge.
///
/// The bottom navigation no longer uses it: a shape spanning the width reads as
/// a bar however irregular its edge is, so the nav sits on plain paper with a
/// transparent-to-paper fade. It stays in the kit for a full-width wash that is
/// not a navigation bar.
class PaintSwash extends StatelessWidget {
  const PaintSwash({
    super.key,
    required this.seed,
    required this.color,
    this.top = 14,
    this.wobble = 5,
    this.layers = 3,
    this.child,
  });

  final int seed;
  final Color color;

  /// Where the average top edge sits, measured from the top of the box.
  final double top;

  /// How far the edge wanders above and below [top].
  final double wobble;

  final int layers;
  final Widget? child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _PaintSwashPainter(
        seed: seed,
        color: color,
        top: top,
        wobble: wobble,
        layers: layers,
      ),
      child: child,
    ),
  );
}

class _PaintSwashPainter extends CustomPainter {
  const _PaintSwashPainter({
    required this.seed,
    required this.color,
    required this.top,
    required this.wobble,
    required this.layers,
  });

  final int seed;
  final Color color;
  final double top;
  final double wobble;
  final int layers;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final count = layers.clamp(1, 3);
    final rect = Offset.zero & size;
    for (var index = 0; index < count; index++) {
      final path = paintSwashPath(
        size: size,
        seed: seed + index * 131,
        top: top + index * 2.5,
        wobble: wobble,
      );
      final fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.30),
          ],
        ).createShader(rect);
      canvas.drawPath(path, fill);
    }
    // Pooling edge along the top. It is soft and low contrast on purpose: a
    // crisp line here would be the hairline the navigation is losing.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = paintTone(color, -0.3).withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
    canvas.drawPath(
      paintSwashPath(
        size: size,
        seed: seed,
        top: top,
        wobble: wobble,
      ),
      rim,
    );

    // A couple of drops thrown above the edge, so the wash reads as a splash
    // of paint rather than a wavy band.
    final rng = math.Random(seed);
    final dot = Paint()..color = color.withValues(alpha: 0.5);
    for (var i = 0; i < 3; i++) {
      final x = size.width * (0.08 + 0.84 * rng.nextDouble());
      final y = top - 2 - rng.nextDouble() * wobble * 1.6;
      if (y < 1) continue;
      canvas.drawCircle(Offset(x, y), 1.2 + rng.nextDouble() * 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(_PaintSwashPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.color != color ||
      oldDelegate.top != top ||
      oldDelegate.wobble != wobble ||
      oldDelegate.layers != layers;
}
