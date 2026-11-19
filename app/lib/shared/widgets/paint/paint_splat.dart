import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// The main splash: an irregular body with arms, satellite droplets and drips.
///
/// It is the shape the selected bottom-navigation tab sits on, and the splash the
/// outline comes from [paintBlob], so it is seeded and cached rather than
/// redrawn from a fresh random number on every frame.
///
/// **Content safety.** [child] is laid out inside the inner rect left by
/// [padding]; the paint is drawn in the full box and spills into that band. The
/// arms, droplets and drips are placed on the *outside* of the outline, so they
/// can never land on a label or a tap target however the seed falls. The paint
/// is allowed to leave the widget box: a `Stack` with `Clip.none`, or a gap in
/// the surrounding layout, gives it room. Shrinking the wobble until it fits
/// instead would put the straight edges back.
///
/// **Motion.** [progress] runs the 「ビチャ」 splash: the body overshoots its
/// resting size and settles, the arms shoot out of the edge, the droplets fly
/// out to their resting spots and the drips extend afterwards. The body never
/// scales below [minScale], so content-carrying splashes keep their safe rect
/// covered for the whole animation. Reduced motion paints the final state with
/// no motion at all.
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
    this.arms,
    this.armLength = 0.16,
    this.origin,
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

  /// The safe rect inset. Arms, droplets, drips and the wobbling edge live in
  /// this band.
  final EdgeInsets padding;

  /// Requested corner radius of the underlying rounded rectangle. It is capped
  /// by [padding] so the paint can never cut into the safe rect.
  final double corner;

  /// How far the outline wanders in and out, as a fraction of the short side.
  /// 0.04–0.10 is the range that reads as paint; below it the edge still looks
  /// ruled.
  final double wobble;

  /// 3–10 reads as a splash; more turns into noise.
  final int droplets;

  /// 0–2. Each drip hangs off the bottom edge.
  final int drips;

  /// Multiplies the whole splash, used to lay a second splash over the first.
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

  /// Number of arms. Null picks 3–7 from the seed, 0 draws none.
  final int? arms;

  /// Arm length as a fraction of the short side. Wide content passes a smaller
  /// value so the tips land in the gap around the card instead of on the
  /// neighbouring one.
  final double armLength;

  /// Where the splash grows from, in the box's own alignment. Null grows from
  /// the centre. A declaration bursts from the button, so it passes the button's
  /// alignment and the paint appears to be thrown from there.
  final Alignment? origin;

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
      arms: arms,
      armLength: armLength,
      origin: origin,
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
    required this.arms,
    required this.armLength,
    required this.origin,
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
  final int? arms;
  final double armLength;
  final Alignment? origin;
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
      arms: arms,
      armLength: armLength,
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

    // Growing from [origin] instead of the centre is what makes a declaration
    // read as paint thrown from the button rather than as a card inflating.
    final anchor = switch (origin) {
      final Alignment value => Offset(
        size.width * (value.x + 1) / 2,
        size.height * (value.y + 1) / 2,
      ),
      null => blob.center,
    };
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.scale(scale, scale);
    canvas.translate(-anchor.dx, -anchor.dy);

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

    // The arms are separate filled shapes that overlap the body by a few dp.
    // The gradient shader lives in canvas space, so the overlap is invisible and
    // the arm still reads as part of the same splash. Drawing them separately is
    // what lets each one shoot out on its own instead of the whole body being
    // scaled.
    for (var i = 0; i < blob.arms.length; i++) {
      paintArm(canvas, fill, blob.arms[i], progress: t, index: i);
    }

    // Droplets and drips take the darker end of the gradient so they read as
    // the same paint thrown off the body rather than as separate dots.
    final thrown = Paint()..color = colors.last;
    for (final drip in blob.drips) {
      paintDrip(canvas, thrown, drip, progress: t);
    }
    for (var i = 0; i < blob.droplets.length; i++) {
      paintDroplet(
        canvas,
        thrown,
        blob.droplets[i],
        center: blob.center,
        progress: t,
        index: i,
      );
    }
    canvas.restore();
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
      oldDelegate.arms != arms ||
      oldDelegate.armLength != armLength ||
      oldDelegate.origin != origin ||
      oldDelegate.progress != progress ||
      oldDelegate.padding != padding ||
      !listEquals(oldDelegate.colors, colors);
}
