import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// A hand-painted underline.
///
/// The path is a closed, variable-width ribbon: thick through the middle,
/// tapering to nothing at both ends, with a ragged edge and a slow drift. That
/// is what a loaded brush leaves on paper, and it replaces the thin squiggle
/// that used to sit under section titles and the logo.
class BrushStroke extends StatelessWidget {
  const BrushStroke({
    super.key,
    required this.seed,
    required this.color,
    this.size = const Size(120, 10),
  });

  /// Seeded so the stroke keeps its exact raggedness across rebuilds.
  final int seed;

  final Color color;

  /// Width and maximum thickness of the stroke.
  final Size size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: _BrushStrokePainter(seed: seed, color: color),
        ),
      ),
    ),
  );
}

class _BrushStrokePainter extends CustomPainter {
  const _BrushStrokePainter({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawPath(
      paintBrushPath(size: size, seed: seed),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BrushStrokePainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.color != color;
}
