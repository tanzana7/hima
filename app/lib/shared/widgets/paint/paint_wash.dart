import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// A watercolour wash for card and section backgrounds.
///
/// **One layer.** The wash is a single filled silhouette from the same body
/// generator the splash uses, with a smaller wobble: enough that the edge bulges
/// and dents and the corners do not match, so a card reads as a wet spread of
/// paint rather than as a frosted rectangle.
///
/// It used to stack two or three translucent blobs, each with its own seed and a
/// few dp of offset. Every one of them also carried a pooling rim, so the eye saw
/// two or three outlines tracing the same rectangle and read the card as frosted
/// glass with several edges. The tonal variation that the stacking was there for
/// now lives *inside* the one layer: a two-tone gradient across the body plus one
/// or two soft radial blooms clipped to it. A bloom has no edge of its own, so it
/// deepens part of the wash without adding an outline.
///
/// A single faint pooling rim follows the real outline. That line is what
/// separates a wash from a flat pastel rectangle, and it replaces the thin border
/// cards used to carry. There is no shadow and no highlight: a drop shadow is
/// what made the first version look like glass.
///
/// Like [PaintSplat] the shapes are seeded and cached, the child is laid out in
/// the inner rect left by [padding], and the paint spills into that band and past
/// the widget box.
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

  /// The hue. The tonal gradient, the blooms and the rim are derived from it, so
  /// one token is enough.
  final Color color;

  final Widget? child;
  final Size size;
  final EdgeInsets padding;
  final double corner;

  /// How many tonal passes the wash gets, 1–3. One is a plain gradient; 2–3 add
  /// one or two soft interior blooms. It no longer means "stacked blobs": the
  /// passes never draw an outline of their own.
  final int layers;

  /// Wobble of the edge as a fraction of the short side. 0.02–0.05 is the wash
  /// range: a splash uses 0.04–0.10.
  final double wobble;

  /// Draws the single pooling edge. Off for very small washes where it would read
  /// as a hairline.
  final bool rim;

  /// Short lobes where the wash spread. 0 keeps a plain, if still uneven, blob.
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

  /// Alpha of the single body fill.
  ///
  /// It replaces the three 50% layers the wash used to stack, which composited
  /// to about 0.87 in the middle of a card. Matching that keeps the card's
  /// weight and the contrast the captions on it were measured against, while
  /// leaving the interior light enough for the blooms to show.
  static const _bodyAlpha = 0.86;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // One silhouette for the whole wash, so there is exactly one outline.
    final body = paintSilhouette(
      size: size,
      seed: seed,
      padding: padding,
      corner: corner,
      wobble: wobble,
      arms: arms,
      armLength: armLength,
    );

    // Tonal variation inside that one layer: a two-tone diagonal, the way a wet
    // wash dries unevenly. A single flat value reads as a vector shape however
    // irregular its outline is.
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            paintTone(color, 0.08).withValues(alpha: _bodyAlpha),
            paintTone(color, -0.08).withValues(alpha: _bodyAlpha),
          ],
        ).createShader(Offset.zero & size),
    );

    // Secondary passes are interior blooms, never offset copies of the outline.
    // A radial gradient has no edge to trace, and clipping it to the body means
    // it can only deepen the paint it sits on.
    final blooms = layers.clamp(1, 3) - 1;
    if (blooms > 0) {
      final rng = math.Random(seed ^ 0x2f7d);
      final shortSide = math.min(size.width, size.height);
      canvas.save();
      canvas.clipPath(body);
      for (var index = 0; index < blooms; index++) {
        // Kept off the very edge: a bloom centred on the outline would darken
        // the rim band and read as a second outline after all.
        final center = Offset(
          size.width * (0.3 + 0.4 * rng.nextDouble()),
          size.height * (0.3 + 0.4 * rng.nextDouble()),
        );
        final radius = shortSide * (0.5 + 0.3 * rng.nextDouble());
        final tone = paintTone(
          color,
          index.isEven ? -0.16 : 0.16,
        ).withValues(alpha: 0.18);
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [tone, tone.withValues(alpha: 0)],
            ).createShader(Rect.fromCircle(center: center, radius: radius)),
        );
      }
      canvas.restore();
    }

    if (rim) {
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = paintTone(color, -0.3).withValues(alpha: 0.22)
          // A small blur keeps the pooling edge soft. It is deliberately tiny:
          // the home screen scrolls a dozen of these cards, and a large sigma
          // would cost a saveLayer per card per frame.
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );
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
