import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// The two small marks that survive from the doodle set: a star and a heart.
///
/// Both are now filled paint dabs rather than line drawings. The star is a
/// five-lobed splash, so its points are round and uneven; the heart keeps its
/// silhouette but is filled and gets a satellite drop. Line-based marks are
/// gone from the kit, so nothing on the home screen is drawn as a stroke.
enum PaintMarkKind { star, heart }

class PaintMark extends StatelessWidget {
  const PaintMark({
    super.key,
    required this.kind,
    required this.seed,
    required this.color,
    this.size = 16,
  });

  final PaintMarkKind kind;
  final int seed;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _PaintMarkPainter(kind: kind, seed: seed, color: color),
        ),
      ),
    ),
  );
}

class _PaintMarkPainter extends CustomPainter {
  const _PaintMarkPainter({
    required this.kind,
    required this.seed,
    required this.color,
  });

  final PaintMarkKind kind;
  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [paintTone(color, 0.22), color],
      ).createShader(Offset.zero & size);
    final dot = Paint()..color = color;
    switch (kind) {
      case PaintMarkKind.star:
        // Five lobes with a strong wobble: a star thrown at the paper, not a
        // polygon with corners.
        final blob = paintBlob(
          size: size,
          seed: seed,
          padding: EdgeInsets.zero,
          corner: 0,
          wobble: 0.42,
          dropletCount: 2,
          dripCount: 0,
          lobes: 5,
          circleBase: true,
        );
        canvas.drawPath(blob.path, fill);
        for (final droplet in blob.droplets) {
          canvas.drawCircle(droplet.center, droplet.radius * 0.8, dot);
        }
      case PaintMarkKind.heart:
        final w = size.width;
        final h = size.height;
        final path = Path()
          ..moveTo(w / 2, h * 0.92)
          ..cubicTo(-w * 0.22, h * 0.52, w * 0.14, -h * 0.08, w / 2, h * 0.3)
          ..cubicTo(w * 0.86, -h * 0.08, w * 1.22, h * 0.52, w / 2, h * 0.92)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawCircle(Offset(w * 0.94, h * 0.1), w * 0.1, dot);
    }
  }

  @override
  bool shouldRepaint(_PaintMarkPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.seed != seed ||
      oldDelegate.color != color;
}
