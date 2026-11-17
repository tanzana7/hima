import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// The main splash: an irregular blob with satellite droplets and drips.
///
/// It is the shape the hero and the selected bottom-navigation tab sit on. The
/// outline comes from [paintBlob], so it is seeded and cached rather than
/// redrawn from a fresh random number on every frame.
///
/// **Content safety.** [child] is laid out inside the inner rect left by
/// [padding]; the paint is drawn in the full box and spills into that band. The
/// droplets and drips are placed on the *outside* of the outline, so they can
/// never land on a label or a tap target however the seed falls.
///
/// **Motion.** [progress] runs the 「ビチャ」 splash: the blob overshoots its
/// resting size and settles, the droplets fly out from the edge to their
/// resting spots, and the drips extend afterwards. The blob never scales below
/// 1, so the content is on paint for the whole animation. Reduced motion paints
/// the final state with no motion at all.
class PaintSplat extends StatelessWidget {
  const PaintSplat({
    super.key,
    required this.seed,
    required this.colors,
    this.child,
    this.size = Size.zero,
    this.padding = const EdgeInsets.all(20),
    this.corner = 36,
    this.wobble = 0.05,
    this.droplets = 6,
    this.drips = 1,
    this.grow = 1,
    this.progress = 1,
    this.minScale = 1,
  });

  /// Keeps the silhouette stable for a given card, friend or section.
  final int seed;

  /// One colour for a flat fill, two for a tonal gradient (top-left to
  /// bottom-right). A single flat value reads as vector art, so the two-colour
  /// form is the default in the app.
  final List<Color> colors;

  /// Laid out inside the safe rect. Null paints a bare splash of [size].
  final Widget? child;

  /// Used only when there is no [child]; otherwise the splash follows the
  /// child's size.
  final Size size;

  /// The safe rect inset. Droplets, drips and the wobbling edge live in this
  /// band.
  final EdgeInsets padding;

  /// Requested corner radius of the underlying rounded rectangle. It is capped
  /// by [padding] so the paint can never cut into the safe rect.
  final double corner;

  /// How far the outline may wander outward, as a fraction of the radius.
  final double wobble;

  /// 3–10 reads as a splash; more turns into noise.
  final int droplets;

  /// 0–2. Each drip hangs off the bottom edge.
  final int drips;

  /// Multiplies the outline, used to lay a second splash over the first.
  final double grow;

  /// 0 → 1 splash-in. Values above 1 are clamped.
  final double progress;

  /// Size the body starts at, as a fraction of its resting size, so it can fly
  /// in and land. The default of 1 keeps the body at its resting size for the
  /// whole animation, which is what a splash that carries content needs: the
  /// safe rect stays covered, so text on the paint never loses its contrast.
  ///
  /// A value below 1 leaves the safe rect uncovered while the body is small, so
  /// only use it for a decorative splash painted *over* another one.
  final double minScale;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final painter = _PaintSplatPainter(
      seed: seed,
      colors: colors,
      padding: padding,
      corner: corner,
      wobble: wobble,
      droplets: droplets,
      drips: drips,
      grow: grow,
      minScale: minScale,
      progress: reduceMotion ? 1 : progress.clamp(0.0, 1.0),
    );
    final childWidget = child;
    // RepaintBoundary: a splash is a static picture between animations, so it
    // must not be repainted when a sibling card rebuilds while scrolling.
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

class _PaintSplatPainter extends CustomPainter {
  const _PaintSplatPainter({
    required this.seed,
    required this.colors,
    required this.padding,
    required this.corner,
    required this.wobble,
    required this.droplets,
    required this.drips,
    required this.grow,
    required this.minScale,
    required this.progress,
  });

  final int seed;
  final List<Color> colors;
  final EdgeInsets padding;
  final double corner;
  final double wobble;
  final int droplets;
  final int drips;
  final double grow;
  final double minScale;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final blob = paintBlob(
      size: size,
      seed: seed,
      padding: padding,
      corner: corner,
      wobble: wobble,
      dropletCount: droplets,
      dripCount: drips,
      grow: grow,
    );
    final t = progress;
    // The body flies in from [minScale] and lands with an overshoot, so a
    // declaration reads as paint being thrown rather than as a rectangle
    // changing colour. At the default minScale of 1 the ramp contributes
    // nothing and only the small overshoot is left, which keeps the safe rect
    // covered for a splash that carries content. A splash that starts smaller
    // gets a bigger overshoot, because it has distance to travel.
    final ramp = Curves.easeOutCubic.transform(t);
    final overshoot = 0.05 + 0.10 * (1 - minScale);
    final scale =
        minScale + (1 - minScale) * ramp + overshoot * math.sin(math.pi * t);

    canvas.save();
    canvas.translate(blob.center.dx, blob.center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-blob.center.dx, -blob.center.dy);

    final fill = Paint();
    if (colors.length > 1) {
      fill.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(Offset.zero & size);
    } else {
      fill.color = colors.first;
    }
    canvas.drawPath(blob.path, fill);

    // Droplets and drips take the darker end of the gradient so they read as
    // the same paint thrown off the body rather than as separate dots.
    final thrown = Paint()..color = colors.last;
    for (final drip in blob.drips) {
      _paintDrip(canvas, thrown, drip, t);
    }
    for (var i = 0; i < blob.droplets.length; i++) {
      _paintDroplet(canvas, thrown, blob.droplets[i], blob.center, t, i);
    }
    canvas.restore();
  }

  void _paintDrip(Canvas canvas, Paint paint, PaintDrip drip, double t) {
    // Drips land after the body: the paint has to arrive before it can run.
    final stagger = Curves.easeOutCubic.transform(
      ((t - 0.3) / 0.7).clamp(0.0, 1.0),
    );
    if (stagger <= 0) return;
    final end = Offset.lerp(drip.start, drip.end, stagger)!;
    final delta = end - drip.start;
    final length = delta.distance;
    if (length < 0.5) return;
    final direction = delta / length;
    final normal = Offset(-direction.dy, direction.dx);
    final half = drip.width * 0.5;
    final tip = drip.width * 0.22;
    final path = Path()
      ..moveTo(
        drip.start.dx + normal.dx * half,
        drip.start.dy + normal.dy * half,
      )
      ..lineTo(end.dx + normal.dx * tip, end.dy + normal.dy * tip)
      ..lineTo(end.dx - normal.dx * tip, end.dy - normal.dy * tip)
      ..lineTo(
        drip.start.dx - normal.dx * half,
        drip.start.dy - normal.dy * half,
      )
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(end, drip.bead * (0.45 + 0.55 * stagger), paint);
  }

  void _paintDroplet(
    Canvas canvas,
    Paint paint,
    PaintDroplet droplet,
    Offset center,
    double t,
    int index,
  ) {
    // Staggered so the ring of droplets leaves the blob in sequence instead of
    // popping out as one ring.
    final stagger = Curves.easeOutCubic.transform(
      ((t - 0.08 * index) / 0.55).clamp(0.0, 1.0),
    );
    if (stagger <= 0) return;
    final fly = 0.35 + 0.65 * stagger;
    final position = center + (droplet.center - center) * fly;
    final radius = droplet.radius * (0.45 + 0.55 * stagger);
    final neckFrom = droplet.neckFrom;
    if (neckFrom != null && stagger > 0.5) {
      final from = center + (neckFrom - center) * fly;
      final delta = position - from;
      final length = delta.distance;
      if (length > 0.5) {
        final direction = delta / length;
        final normal = Offset(-direction.dy, direction.dx);
        final wide = droplet.neckWidth;
        final narrow = droplet.neckWidth * 0.4;
        final path = Path()
          ..moveTo(from.dx + normal.dx * wide, from.dy + normal.dy * wide)
          ..lineTo(
            position.dx + normal.dx * narrow,
            position.dy + normal.dy * narrow,
          )
          ..lineTo(
            position.dx - normal.dx * narrow,
            position.dy - normal.dy * narrow,
          )
          ..lineTo(from.dx - normal.dx * wide, from.dy - normal.dy * wide)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
    canvas.drawCircle(position, radius, paint);
  }

  @override
  bool shouldRepaint(_PaintSplatPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.corner != corner ||
      oldDelegate.wobble != wobble ||
      oldDelegate.droplets != droplets ||
      oldDelegate.drips != drips ||
      oldDelegate.grow != grow ||
      oldDelegate.minScale != minScale ||
      oldDelegate.progress != progress ||
      oldDelegate.padding != padding ||
      !listEquals(oldDelegate.colors, colors);
}
