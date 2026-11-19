import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'paint_geometry.dart';
import 'paint_texture.dart';

/// The paper a [PaintThick] keeps clear around itself, in dp.
///
/// It is smaller than [paintMaxBleed] on purpose: the blob throws a few short
/// arms and droplets, not a full ring, so a caller that reserves this much paper
/// gets the whole painted extent without pushing the rest of the screen apart.
const double paintThickBleed = 24;

/// A thick blob of acrylic: a loaded brush-load of paint with a body you can
/// see the depth of.
///
/// The kit already had a splash ([PaintSplat]), a wash ([PaintWash]) and a
/// brushed band ([BrushSwipe]); this is the shape the home hero and the
/// activity picker needed instead of a band, because a band is a rectangle seen
/// from the side and the hero has to read as a lump of paint on the paper.
///
/// * **Bristles.** [PaintDetail.streak] is tinted inside the body. The fill
///   keeps its `AppColors` hue and only its lightness is broken up, the way a
///   loaded brush leaves it.
/// * **Gloss.** A soft sheen and short specular marks are clipped to the body,
///   so child-bearing blobs never show the safe rectangle as a second edge.
/// * **Dry edge.** [PaintDetail.dryBrush] punches holes out of that edge band, so
///   the outline is not just wobbly but torn up like paint pulled off a brush.
/// * **Depth.** The fill gradient and silhouette wobble give the body volume
///   without a rectangular inner rim.
/// * **Wipe.** [wipe] takes the paint off from the left along a seeded, ragged
///   front. The silhouette provides the paint edge without a tiled streak band.
///
/// Like the rest of the kit it is seeded and cached, keeps its child inside
/// [padding], spills into the band around it, and paints the finished state when
/// `MediaQuery.disableAnimationsOf` is true.
class PaintThick extends StatelessWidget {
  const PaintThick({
    super.key,
    required this.seed,
    required this.colors,
    this.child,
    this.size = Size.zero,
    this.padding = const EdgeInsets.all(20),
    this.corner = 999,
    this.wobble = 0.04,
    this.droplets = 8,
    this.drips = 1,
    this.arms = 3,
    this.armLength = 0.035,
    this.progress = 1,
    this.wipe = 0,
    this.gloss = 1,
    this.bristles = true,
    this.dryEdge = true,
    this.detailUnderContent = 1,
  });

  /// Keeps the blob's exact silhouette across rebuilds, and lets the hero paint
  /// the same lump in both states so nothing shows around the edges when one is
  /// laid over the other.
  final int seed;

  /// One colour for a flat fill, two for the light-to-deep gradient of a thick
  /// body. A single flat value reads as a vector shape, so two is the norm.
  final List<Color> colors;

  /// Laid out inside the safe rect. Null paints a bare blob of [size].
  final Widget? child;

  /// Used only when there is no [child].
  final Size size;

  /// The safe rect inset. The arms, droplets, drips and the dry edge live
  /// outside it, so decoration can never land on a label or a tap target.
  final EdgeInsets padding;

  /// Requested corner radius of the underlying rounded rectangle, capped by
  /// [padding] so the paint cannot cut into the safe rect.
  final double corner;

  /// How far the outline wanders, as a fraction of the short side.
  final double wobble;

  /// 4–10 detached drops. More turns into noise.
  final int droplets;

  /// 0–2 tongues of paint running off the bottom edge.
  final int drips;

  /// Lobes where the paint spread. 0 gives a plain, still uneven blob.
  final int? arms;

  /// Lobe length as a fraction of the short side.
  final double armLength;

  /// 0 → 1 landing. The body never shrinks below its resting size, so content
  /// on the paint always has paint under it; only the arms, the drops and a
  /// small overshoot move.
  final double progress;

  /// 0 → the whole blob, 1 → nothing left. The paint comes off from the left
  /// behind a seeded, dry-brush front.
  final double wipe;

  /// 0 turns the shine off, 1 is the normal gloss.
  final double gloss;

  /// Draws the bristle marks inside the paint.
  final bool bristles;

  /// Tears the outline up with the dry-brush map. Off for a small dab, where it
  /// would eat most of the paint rather than breaking up an edge.
  final bool dryEdge;

  /// How much of the bristle detail is left inside the content's safe rect.
  ///
  /// 1 keeps it everywhere. Lower values fade it out under whatever sits on the
  /// paint, which matters wherever light text is measured against the fill: a
  /// bright bristle can lift the colour enough to reduce contrast. The fade is
  /// a radial mask, so there is no seam where it starts.
  final double detailUnderContent;

  @override
  Widget build(BuildContext context) {
    PaintTextures.instance.preload();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final childWidget = child;
    return ListenableBuilder(
      // The detail maps decode asynchronously; this repaints the blob with them
      // once instead of decoding inside the painter.
      listenable: PaintTextures.instance.revision,
      builder: (context, _) {
        final painter = _PaintThickPainter(
          seed: seed,
          colors: colors,
          padding: padding,
          corner: corner,
          wobble: wobble,
          droplets: droplets,
          drips: drips,
          arms: arms,
          armLength: armLength,
          progress: reduceMotion ? 1 : progress.clamp(0.0, 1.0),
          wipe: wipe.clamp(0.0, 1.0),
          gloss: gloss,
          bristles: bristles,
          dryEdge: dryEdge,
          detailUnderContent: detailUnderContent.clamp(0.0, 1.0),
          detailRevision: PaintTextures.instance.revision.value,
        );
        // RepaintBoundary: the blob is a still picture between animations, so it
        // must not repaint when a sibling card rebuilds while scrolling.
        return RepaintBoundary(
          child: childWidget == null
              ? CustomPaint(size: size, painter: painter)
              : CustomPaint(
                  painter: painter,
                  child: Padding(padding: padding, child: childWidget),
                ),
        );
      },
    );
  }
}

class _PaintThickPainter extends CustomPainter {
  const _PaintThickPainter({
    required this.seed,
    required this.colors,
    required this.padding,
    required this.corner,
    required this.wobble,
    required this.droplets,
    required this.drips,
    required this.arms,
    required this.armLength,
    required this.progress,
    required this.wipe,
    required this.gloss,
    required this.bristles,
    required this.dryEdge,
    required this.detailUnderContent,
    required this.detailRevision,
  });

  final int seed;
  final List<Color> colors;
  final EdgeInsets padding;
  final double corner;
  final double wobble;
  final int droplets;
  final int drips;
  final int? arms;
  final double armLength;
  final double progress;
  final double wipe;
  final double gloss;
  final bool bristles;
  final bool dryEdge;
  final double detailUnderContent;
  final int detailRevision;

  /// The margin between the blob's edge and the safe rect used by the dry edge.
  static final _rimCache = PaintCache<Path>(capacity: 32);

  PaintBlob _blobFor(Size size) => paintBlob(
    size: size,
    seed: seed,
    padding: padding,
    corner: corner,
    wobble: wobble,
    dropletCount: droplets,
    dripCount: drips,
    arms: arms,
    armLength: armLength,
  );

  Path _bodyFor(Size size) => paintSilhouette(
    size: size,
    seed: seed,
    padding: padding,
    corner: corner,
    wobble: wobble,
    arms: arms,
    armLength: armLength,
  );

  /// The rect the content is laid out in: where labels and targets sit.
  Rect _safeFor(Size size) => Rect.fromLTRB(
    padding.left,
    padding.top,
    math.max(padding.left, size.width - padding.right),
    math.max(padding.top, size.height - padding.bottom),
  );

  Path _rimFor(Size size) =>
      _rimCache.get((size, seed, padding, corner, wobble, arms, armLength), () {
        final body = _bodyFor(size);
        final safe = _safeFor(size);
        if (safe.isEmpty) return body;
        return Path.combine(
          PathOperation.difference,
          body,
          Path()..addRect(safe),
        );
      });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || wipe >= 1) return;
    final rect = Offset.zero & size;
    final blob = _blobFor(size);
    final light = paintTone(colors.first, 0.14);
    final deep = paintTone(colors.last, -0.10);

    canvas.save();
    if (progress < 1) {
      // The landing: the body overshoots and settles, the arms shoot out and the
      // drops fly. It never scales below 1, so the safe rect stays covered.
      final scale = 1 + 0.06 * math.sin(math.pi * progress);
      canvas.translate(blob.center.dx, blob.center.dy);
      canvas.scale(scale);
      canvas.translate(-blob.center.dx, -blob.center.dy);
    }
    if (wipe > 0) {
      // The paint comes off, so what is left is clipped to the area the wipe has
      // not reached. The kept area runs past the box: the arms and the drops
      // living outside it must not be cut off by the wipe either.
      canvas.clipPath(
        paintWipeKeptPath(size: size, progress: wipe, seed: seed),
      );
    }

    // One layer for the whole blob: the dry-brush edge is punched out with
    // `dstOut`, which erases the current layer. Straight onto the canvas it
    // would also erase the paper painted behind the blob.
    final bounds = rect.inflate(paintMaxBleed + 24);
    canvas.saveLayer(bounds, Paint());
    _paintBody(canvas, rect, blob, light, deep);
    if (bristles) _paintBristles(canvas, size, rect);
    if (gloss > 0) _paintGloss(canvas, size, blob);
    if (dryEdge) _paintDryEdge(canvas, size, rect);
    canvas.restore();

    canvas.restore();
  }

  /// The fill: a light-to-deep gradient across the body, the arms in the same
  /// paint, and the drops and drips in the deeper tone.
  void _paintBody(
    Canvas canvas,
    Rect rect,
    PaintBlob blob,
    Color light,
    Color deep,
  ) {
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [light, colors.first, colors.last, deep],
        stops: const [0, 0.3, 0.72, 1],
      ).createShader(rect);
    canvas.drawPath(blob.path, fill);
    // The arms overlap the body by a few dp. The gradient lives in canvas space,
    // so the seam is invisible and the lobe reads as the same paint spreading.
    final lobes = blob.arms;
    for (var i = 0; i < lobes.length; i++) {
      paintArm(canvas, fill, lobes[i], progress: progress, index: i);
    }
    final thrown = Paint()..color = colors.last;
    for (final drip in blob.drips) {
      paintDrip(canvas, thrown, drip, progress: progress);
    }
    final drops = blob.droplets;
    for (var i = 0; i < drops.length; i++) {
      paintDroplet(
        canvas,
        thrown,
        drops[i],
        center: blob.center,
        progress: progress,
        index: i,
      );
    }
  }

  /// The bristle marks, tinted inside the paint.
  ///
  /// [PaintThick.detailUnderContent] decides whether they run all the way across
  /// the body or fade out under the content: a bright streak lifts the fill, and
  /// where small white type sits on it that lift costs contrast. The fade is a
  /// radial mask, so the detail never stops along a straight line.
  void _paintBristles(Canvas canvas, Size size, Rect rect) {
    final pass = paintDetail(
      PaintDetail.streak,
      // The streak source is a 512px square of long horizontal marks. Sampling
      // it wider than it is tall keeps the marks running along the stroke
      // instead of turning them into a grid.
      tile: const Size(200, 92),
      angle: -0.05,
      strength: 0.5,
      alpha: 0.9,
    );
    final tooth = paintDetail(
      PaintDetail.grain,
      tile: const Size(140, 140),
      strength: 0.45,
      alpha: 0.45,
      blend: BlendMode.overlay,
    );
    if (pass == null && tooth == null) return;
    final bounds = rect.inflate(paintMaxBleed + 24);
    canvas.save();
    canvas.clipPath(_bodyFor(size));
    if (detailUnderContent < 1) {
      canvas.saveLayer(bounds, Paint());
    }
    if (pass != null) canvas.drawRect(rect, pass);
    if (tooth != null) canvas.drawRect(rect, tooth);
    if (detailUnderContent < 1) {
      final safe = _safeFor(size);
      // Flat across the content, then a ramp back to full strength over the
      // paint's own band: the corner of the safe rect is where the ramp starts.
      final flat = Offset(safe.width / 2, safe.height / 2).distance;
      final radius = math.max(
        flat + 1,
        math.max(size.width, size.height) * 0.62,
      );
      final stop = (flat / radius).clamp(0.0, 0.98);
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: detailUnderContent),
              Colors.white.withValues(alpha: detailUnderContent),
              Colors.white,
            ],
            stops: [0, stop, 1],
          ).createShader(Rect.fromCircle(center: safe.center, radius: radius)),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  /// The shine follows the silhouette so child-bearing blobs never reveal the
  /// rectangular safe area as a second edge.
  void _paintGloss(Canvas canvas, Size size, PaintBlob blob) {
    final body = blob.path;

    // Keep the white sheen soft so it adds wet gloss without washing out the
    // declared hero's white heading.
    final sheenRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.55);
    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.07 * gloss),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(sheenRect),
    );

    // These short ovals sit above the child-safe area. Drawing them directly on
    // the body avoids the rectangular inner edge a safe-area rim creates.
    final top = math.max(6.0, padding.top);
    for (final (start, end, weight) in const <(double, double, double)>[
      (0.16, 0.46, 0.55),
      (0.58, 0.72, 0.35),
    ]) {
      final mark = Rect.fromLTRB(
        size.width * start,
        top * 0.30,
        size.width * end,
        top * 0.30 + math.max(4.0, top * 0.32),
      );
      canvas.drawOval(
        mark,
        Paint()
          ..color = Colors.white.withValues(alpha: weight * gloss)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );
    }
    canvas.restore();
  }

  /// Tears the edge up with the dry-brush map, so the outline is broken paint
  /// rather than a smooth silhouette.
  void _paintDryEdge(Canvas canvas, Size size, Rect rect) {
    final erase = paintDetailErase(
      PaintDetail.dryBrush,
      tile: const Size(150, 92),
      angle: 0.02,
      strength: 0.55,
    );
    if (erase == null) return;
    canvas.save();
    canvas.clipPath(_rimFor(size));
    canvas.clipRect(rect.inflate(4));
    canvas.drawRect(rect.inflate(4), erase);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaintThickPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.padding != padding ||
      oldDelegate.corner != corner ||
      oldDelegate.wobble != wobble ||
      oldDelegate.droplets != droplets ||
      oldDelegate.drips != drips ||
      oldDelegate.arms != arms ||
      oldDelegate.armLength != armLength ||
      oldDelegate.progress != progress ||
      oldDelegate.wipe != wipe ||
      oldDelegate.gloss != gloss ||
      oldDelegate.bristles != bristles ||
      oldDelegate.dryEdge != dryEdge ||
      oldDelegate.detailUnderContent != detailUnderContent ||
      oldDelegate.detailRevision != detailRevision ||
      !_sameColors(oldDelegate.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
