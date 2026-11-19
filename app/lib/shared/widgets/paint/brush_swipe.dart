import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'paint_geometry.dart';

/// A wide brush stroke: a band painted with one sideways swipe of a fat brush.
///
/// It is the backdrop of the login screen, and it replaces
/// the big splash there. The splash read as a rectangle with growths — a horn
/// on top, an arm on the side, a drip below — because its arms were lobes stuck
/// onto a body that was still a box. A stroke has no growths: it is one band
/// whose two ends say what happened at the two ends of the movement. The left
/// end is rounded where the brush touched down loaded; the right end breaks into
/// uneven fingers with rounded tips and throws splatter where the paint ran out.
///
/// **Content safety.** [child] is laid out inside [padding], and the widget
/// additionally reserves [paintSwipeContentInset] on the right for the dry end
/// and the splatter. That inset replaces `padding.right` rather than being added
/// to it — the two used to be summed, which pushed the content left of the
/// stroke's own centre. The solid band therefore always covers the padded
/// content, and the fingers, the dry streaks and the splatter all start to the
/// right of it: no hole in the paint can run under a label.
///
/// **Centring.** Both ends of the stroke are pinned to the box rather than to
/// the content — the loaded start 4dp from the left edge, the longest finger
/// 14dp from the right (see [paintSwipeContentInset]) — so the band reads as
/// centred on the screen. Its content, however, is inset by the dry end on the
/// right only, which leaves it left of the box centre. [centerContent] gives the
/// left the same inset, for a caller whose content has to share the axis of the
/// centred elements below it.
///
/// **Fit.** The whole stroke — fingers and splatter included — stays inside
/// the widget's width, which is the opposite of the splash: a stroke cut off by
/// the screen edge reads as a rectangle again. On a narrow box the fingers and
/// the splatter get shorter instead of being clipped.
///
/// **Motion.** [progress] reveals the stroke from left to right behind a soft,
/// frayed leading edge, and the splatter arrives once the brush has reached the
/// end of the body. Reduced motion paints the finished stroke.
class BrushSwipe extends StatelessWidget {
  const BrushSwipe({
    super.key,
    required this.seed,
    required this.colors,
    this.child,
    this.size = Size.zero,
    this.padding = const EdgeInsets.all(20),
    this.endInset,
    this.centerContent = false,
    this.droplets,
    this.progress = 1,
  });

  /// Keeps the stroke's exact silhouette across rebuilds, so the login's two
  /// strokes stay aligned and a card does not change shape while scrolling.
  final int seed;

  /// One colour for a flat fill, two for a tonal gradient (top-left to
  /// bottom-right). A single flat value reads as vector art, so the two-colour
  /// form is the default in the app.
  final List<Color> colors;

  /// Laid out inside the safe rect. Null paints a bare stroke of [size].
  final Widget? child;

  /// Used only when there is no [child]; otherwise the stroke follows the
  /// child's size.
  final Size size;

  /// The safe rect inset. The band, the strands and the streaks stay outside
  /// it.
  final EdgeInsets padding;

  /// The room kept to the right of the content for the frayed end and the
  /// splatter. Null derives it from the box width with
  /// [paintSwipeContentInset], and either way it wins over `padding.right`
  /// rather than being added to it.
  ///
  /// A caller that paints two bare strokes over each other (the login) passes
  /// the same value to both, so the two silhouettes line up.
  final double? endInset;

  /// Insets the content by the same amount on the left as on the right, so it
  /// sits on the centre of the box instead of on the centre of the safe rect.
  ///
  /// The login screen needs it: 「hima.」 and 「いま、ひま？」 sit above a centred
  /// caption and button, and the right-only inset left them visibly off that
  /// axis. A caller with left-aligned content leaves this off.
  final bool centerContent;

  /// Overrides the number of droplets flicked off the end. Null paints 16, the
  /// count the mock-up used.
  final int? droplets;

  /// 0 → 1 paint-in. Values above 1 are clamped.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final t = reduceMotion ? 1.0 : progress.clamp(0.0, 1.0).toDouble();
    final childWidget = child;
    // RepaintBoundary: a stroke is a static picture between animations, so it
    // must not repaint when a sibling card rebuilds while scrolling.
    if (childWidget == null) {
      return RepaintBoundary(
        child: CustomPaint(
          size: size,
          // The dry end is left to the painter here: a bare stroke may be
          // sized by its parent rather than by [size], and resolving it from
          // [size] would give a zero-width dry end.
          painter: _BrushSwipePainter(
            seed: seed,
            colors: colors,
            padding: padding,
            endInset: endInset,
            droplets: droplets,
            progress: t,
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset =
              endInset ?? paintSwipeContentInset(constraints.maxWidth);
          // The same rect the geometry uses for the safe rect: the content ends
          // where the dry end begins. The inset is a floor on the caller's
          // padding, not an addition to it.
          final contentPadding = padding.copyWith(
            left: centerContent ? math.max(padding.left, inset) : padding.left,
            right: math.max(padding.right, inset),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BrushSwipePainter(
                    seed: seed,
                    colors: colors,
                    padding: contentPadding,
                    endInset: inset,
                    droplets: droplets,
                    progress: t,
                  ),
                ),
              ),
              Padding(padding: contentPadding, child: childWidget),
            ],
          );
        },
      ),
    );
  }
}

class _BrushSwipePainter extends CustomPainter {
  const _BrushSwipePainter({
    required this.seed,
    required this.colors,
    required this.padding,
    required this.endInset,
    required this.droplets,
    required this.progress,
  });

  final int seed;
  final List<Color> colors;
  final EdgeInsets padding;

  /// Null derives the inset from the size actually painted, which is what a bare
  /// stroke sized by its parent needs.
  final double? endInset;
  final int? droplets;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final swipe = paintSwipe(
      size: size,
      seed: seed,
      padding: padding,
      contentInset: endInset ?? paintSwipeContentInset(size.width),
      droplets: droplets,
    );
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

    final t = progress;
    if (t < 1) {
      // The paint arrives behind a soft, slightly frayed leading edge instead
      // of a straight rule: a straight clip edge is the one thing that would
      // give the stroke away as a shape being wiped on.
      canvas.save();
      canvas.clipPath(
        paintSwipeRevealPath(size: size, progress: t, seed: seed),
      );
    }
    // The dry end is part of this path: the fingers are cut from the same
    // outline, so the paint runs out along the stroke instead of a set of
    // separate shapes being glued onto a hard edge.
    canvas.drawPath(swipe.body, fill);
    // The wet sheen: one faint lighter pass along the upper part of the band.
    // Paint is never one flat value, and without it a wide band looks printed.
    // It is a gradient rather than a shape, so it has no edge of its own, and
    // it is clipped to the body so it can never leave the band.
    //
    // **It has to stay faint.** The band can carry text straight on the paint,
    // the band, and the lightest coral stop is only 3.4:1 against white. A
    // heavier sheen lifts that below 3:1 wherever it covers a label, so the
    // peak is 8% and it fades out in the top 42% of the band — the heading
    // never sees more than about 7%, which keeps it at roughly 3.3:1.
    final sheenRect = Rect.fromLTRB(
      0,
      swipe.band.top,
      size.width,
      swipe.band.top + swipe.band.height * 0.42,
    );
    canvas.save();
    canvas.clipPath(swipe.body);
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(sheenRect),
    );
    canvas.restore();

    if (t < 1) canvas.restore();

    // The splatter only exists once the brush has reached the end of the body:
    // paint cannot flick off a stroke that has not been painted yet.
    final splatterAt = swipe.splatterAt;
    final span = 1 - splatterAt;
    final thrown = span <= 0
        ? (t >= splatterAt ? 1.0 : 0.0)
        : ((t - splatterAt) / span).clamp(0.0, 1.0).toDouble();
    if (thrown <= 0) return;
    final paint = Paint()..color = colors.last;
    for (var i = 0; i < swipe.droplets.length; i++) {
      final droplet = swipe.droplets[i];
      // Staggered so the drops leave the stroke in sequence instead of popping
      // out as one ring.
      final stagger = Curves.easeOutCubic.transform(
        ((thrown - 0.04 * i) / 0.6).clamp(0.0, 1.0).toDouble(),
      );
      if (stagger <= 0) continue;
      canvas.drawCircle(
        droplet.center,
        droplet.radius * (0.4 + 0.6 * stagger),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BrushSwipePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.padding != padding ||
      oldDelegate.endInset != endInset ||
      oldDelegate.droplets != droplets ||
      oldDelegate.progress != progress ||
      !listEquals(oldDelegate.colors, colors);
}
