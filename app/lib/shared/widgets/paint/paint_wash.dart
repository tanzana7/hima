import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// A watercolour wash for card and section backgrounds.
///
/// Two or three translucent blobs of the same hue, slightly offset, so the
/// overlaps darken the way layered paint does. The outline is the same body
/// generator the splash uses, with a smaller wobble: enough that the edge
/// bulges and dents and the corners do not match, so a card reads as a wet
/// spread of paint rather than as a frosted rectangle. A faint darker rim
/// follows the edge of each blob: that pooling line is what separates a wash
/// from a flat pastel rectangle, and it replaces the thin border cards used to
/// carry.
///
/// There is no shadow and no highlight: a drop shadow is what made the first
/// version look like glass.
///
/// Like [PaintSplat] the shapes are seeded and cached, the child is laid out in
/// the inner rect left by [padding], and the paint spills into that band and
/// past the widget box.
class PaintWash extends StatelessWidget {
  const PaintWash({
    super.key,
    required this.seed,
    required this.color,
    this.child,
    this.size = Size.zero,
    this.padding = const EdgeInsets.all(16),
    this.corner = 24,
    this.layers = 3,
    this.wobble = 0.04,
    this.rim = true,
    this.arms = 2,
    this.armLength = 0.025,
  });

  /// Keeps a card's wash the same across rebuilds and scrolling.
  final int seed;

  /// The hue. Layers and the rim are derived from it, so one token is enough.
  final Color color;

  final Widget? child;
  final Size size;
  final EdgeInsets padding;
  final double corner;

  /// 2–3. More layers darken the overlaps into a muddy patch.
  final int layers;

  /// Wobble of the edge as a fraction of the short side. 0.02–0.05 is the wash
  /// range: a splash uses 0.04–0.10.
  final double wobble;

  /// Draws the pooling edge. Off for very small washes where it would read as
  /// a hairline.
  final bool rim;

  /// Short lobes where the wash spread. 0 keeps a plain, if still uneven,
  /// blob.
  final int arms;

  /// Arm length as a fraction of the short side. A wash spreads sideways, not
  /// across the gap to the next card, so this stays small.
  final double armLength;

  @override
  Widget build(BuildContext context) {
    final painter = _PaintWashPainter(
      seed: seed,
      color: color,
      padding: padding,
      corner: corner,
      layers: layers,
      wobble: wobble,
      rim: rim,
      arms: arms,
      armLength: armLength,
    );
    final childWidget = child;
    if (childWidget == null) {
      return RepaintBoundary(
        child: CustomPaint(size: size, painter: painter),
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: painter,
        child: Padding(padding: padding, child: childWidget),
      ),
    );
  }
}

class _PaintWashPainter extends CustomPainter {
  const _PaintWashPainter({
    required this.seed,
    required this.color,
    required this.padding,
    required this.corner,
    required this.layers,
    required this.wobble,
    required this.rim,
    required this.arms,
    required this.armLength,
  });

  final int seed;
  final Color color;
  final EdgeInsets padding;
  final double corner;
  final int layers;
  final double wobble;
  final bool rim;
  final int arms;
  final double armLength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final count = layers.clamp(1, 3);
    final fill = Paint()..color = color.withValues(alpha: 0.5);
    // A small blur keeps the pooling edge soft. It is deliberately tiny: the
    // home screen scrolls a dozen of these cards, and a large sigma would cost
    // a saveLayer per card per frame.
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = paintTone(color, -0.28).withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);

    for (var index = 0; index < count; index++) {
      // Layer 0 is the one that has to cover the safe rect, so it keeps the
      // full box. The others are nudged by a few dp — far enough that the union
      // of the three is a ragged wet edge, close enough that a card in a 12dp
      // grid gap does not paint over its neighbour.
      final dx = index == 0 ? 0.0 : (index.isOdd ? 4.0 : -3.5);
      final dy = index == 0 ? 0.0 : (index.isOdd ? -3.0 : 3.5);
      // Only the base layer grows arms: three layers of arms would be a
      // starburst, not a wash.
      final path = paintSilhouette(
        size: size,
        seed: seed + index * 7919,
        padding: padding,
        corner: corner,
        wobble: wobble,
        arms: index == 0 ? arms : 0,
        armLength: armLength,
      );
      canvas.save();
      canvas.translate(dx, dy);
      canvas.drawPath(path, fill);
      if (rim) canvas.drawPath(path, edge);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PaintWashPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.color != color ||
      oldDelegate.corner != corner ||
      oldDelegate.layers != layers ||
      oldDelegate.wobble != wobble ||
      oldDelegate.rim != rim ||
      oldDelegate.arms != arms ||
      oldDelegate.armLength != armLength ||
      oldDelegate.padding != padding;
}
