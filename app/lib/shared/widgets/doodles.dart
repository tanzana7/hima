import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// The hand-drawn marks sprinkled over the home screen.
enum DoodleKind {
  /// 「///」-style burst: three short strokes fanning out from one corner.
  sparks,

  /// A wavy underline, like the lime swoosh under the `hima.` wordmark.
  squiggle,

  /// A four-point sparkle.
  star,

  /// A small 「!!」.
  bang,

  /// A tiny heart.
  heart,
}

/// One decorative mark.
///
/// The marks are painted with [CustomPainter] rather than shipped as images:
/// each is two or three strokes, they have to tint with the palette tokens and
/// stay crisp at every density, and an asset would need a set of resolutions for
/// no gain in fidelity.
///
/// They are decoration, so they are excluded from semantics and ignore
/// pointers. A mark pops in once and settles at a slight tilt, as if drawn by
/// hand. Reduced motion draws it in place without the pop, and a large text
/// scale drops it entirely: the layout needs the room more than the flourish.
class Doodle extends StatefulWidget {
  const Doodle({
    super.key,
    required this.kind,
    required this.size,
    this.color = AppColors.yellow,
    this.strokeWidth = 3,
    this.tilt = 0,
    this.delay = Duration.zero,
  });

  final DoodleKind kind;
  final Size size;
  final Color color;
  final double strokeWidth;

  /// Final rotation in radians. The pop starts further off-axis so the mark
  /// lands like a pen stroke instead of a stamped icon.
  final double tilt;

  /// Staggers the pop, so a group of marks does not appear as one block.
  final Duration delay;

  /// Above this text scale the marks step aside; the text needs the space.
  static const maxTextScale = 1.5;

  @override
  State<Doodle> createState() => _DoodleState();
}

class _DoodleState extends State<Doodle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
      return;
    }
    _delayTimer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (scale > Doodle.maxTextScale) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value.clamp(0.0, 1.0);
            final pop = Curves.easeOutBack.transform(t);
            return Opacity(
              opacity: Curves.easeOut.transform(t),
              child: Transform.rotate(
                angle: widget.tilt * (0.2 + 0.8 * pop),
                child: Transform.scale(
                  scale: 0.55 + 0.45 * pop,
                  child: CustomPaint(
                    size: widget.size,
                    painter: _DoodlePainter(
                      kind: widget.kind,
                      color: widget.color,
                      strokeWidth: widget.strokeWidth,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  const _DoodlePainter({
    required this.kind,
    required this.color,
    required this.strokeWidth,
  });

  final DoodleKind kind;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case DoodleKind.sparks:
        _paintSparks(canvas, size, stroke);
      case DoodleKind.squiggle:
        _paintSquiggle(canvas, size, stroke);
      case DoodleKind.star:
        _paintStar(canvas, size);
      case DoodleKind.bang:
        _paintBang(canvas, size, stroke);
      case DoodleKind.heart:
        _paintHeart(canvas, size);
    }
  }

  /// Three strokes of different lengths from the bottom-left corner. The uneven
  /// fan is what makes the burst read as a quick pen flick.
  void _paintSparks(Canvas canvas, Size size, Paint stroke) {
    final origin = Offset(0, size.height);
    for (var i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + (i - 1) * 0.55;
      final length = size.height * (i == 1 ? 1.0 : 0.72);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        origin + direction * size.height * 0.12,
        origin + direction * length,
        stroke,
      );
    }
  }

  /// A sampled sine wave: smoother than chained quadratics and it always ends
  /// exactly on the right edge.
  void _paintSquiggle(Canvas canvas, Size size, Paint stroke) {
    const steps = 24;
    final amplitude = size.height / 2 - stroke.strokeWidth / 2;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final point = Offset(
        t * size.width,
        size.height / 2 + math.sin(t * math.pi * 3) * amplitude,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, stroke);
  }

  void _paintStar(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? size.shortestSide / 2 : size.shortestSide / 7;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// Two exclamation strokes, the second shorter, with a dot under each.
  void _paintBang(Canvas canvas, Size size, Paint stroke) {
    final dot = Paint()..color = color;
    for (var i = 0; i < 2; i++) {
      final x = size.width * (i == 0 ? 0.3 : 0.72);
      final top = size.height * (i == 0 ? 0 : 0.12);
      final bottom = size.height * (i == 0 ? 0.62 : 0.7);
      canvas.drawLine(
        Offset(x - stroke.strokeWidth * 0.4, top),
        Offset(x + stroke.strokeWidth * 0.4, bottom),
        stroke,
      );
      canvas.drawCircle(
        Offset(x, size.height * 0.9),
        stroke.strokeWidth * 0.55,
        dot,
      );
    }
  }

  void _paintHeart(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w / 2, h * 0.95)
      ..cubicTo(-w * 0.25, h * 0.55, w * 0.12, -h * 0.1, w / 2, h * 0.28)
      ..cubicTo(w * 0.88, -h * 0.1, w * 1.25, h * 0.55, w / 2, h * 0.95)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DoodlePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// The wobbly backdrop behind the hero.
///
/// A plain rounded rectangle read as a Material card, which is exactly the
/// "too tidy" look the home screen is moving away from. The outline is a
/// superellipse with a slow sine wobble; the wobble only ever pulls it inward,
/// so the shape can never paint over the widgets around it.
class BlobBackdrop extends StatelessWidget {
  const BlobBackdrop({super.key, required this.colors, this.seed = 0});

  /// Gradient stops, top-left to bottom-right.
  final List<Color> colors;

  /// Changes the wobble so two blobs on one screen do not look identical.
  final double seed;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _BlobPainter(colors: colors, seed: seed),
  );
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter({required this.colors, required this.seed});

  final List<Color> colors;
  final double seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawPath(
      _blobPath(size, seed),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) =>
      oldDelegate.seed != seed || !listEquals(oldDelegate.colors, colors);
}

/// A closed, smooth path that fills [size] without exceeding it.
///
/// The outline is a rounded rectangle whose edge is pulled inward by two
/// out-of-phase sine waves and then joined with quadratics through the
/// midpoints, which keeps it round instead of polygonal.
///
/// It used to be a superellipse with a much deeper wobble. That shape ate into
/// the corners enough that the hero's bottom-right control was painted outside
/// the blob, and the only way to keep content inside it was to leave most of
/// the card empty. The rounded rectangle keeps the hand-drawn edge while
/// guaranteeing the band the hero reserves for its content stays inside.
Path _blobPath(Size size, double seed) {
  final width = size.width;
  final height = size.height;
  // The corner radius is capped by the shortest side so a short hero does not
  // turn into a stadium.
  final radius = math.min(AppSpacing.radiusHero, size.shortestSide * 0.34);
  // How far the outline may wander inward. The hero insets its content by 20dp
  // and the corner arc leaves more slack than that, so a few dp of wobble reads
  // as hand-drawn without ever reaching a control.
  final depth = math.min(9.0, size.shortestSide * 0.07);

  const edgeSteps = 6;
  const arcSteps = 4;
  const total = 4 * (edgeSteps + arcSteps);
  final points = <Offset>[];
  var index = 0;

  void add(Offset point, Offset inward) {
    final phase = index++ / total * 2 * math.pi;
    // One slow lobe plus a smaller ripple, normalised to [0, 1]: the pull is
    // always inward, so the shape can never paint over its neighbours.
    final pull =
        0.5 +
        0.35 * math.sin(phase * 3 + seed) +
        0.15 * math.sin(phase * 5 - seed * 1.7);
    points.add(point + inward * (depth * pull));
  }

  void addArc(Offset center, double start) {
    for (var i = 0; i < arcSteps; i++) {
      final angle = start + math.pi / 2 * i / arcSteps;
      final direction = Offset(math.cos(angle), math.sin(angle));
      add(center + direction * radius, -direction);
    }
  }

  void addEdge(Offset from, Offset to, Offset inward) {
    for (var i = 0; i < edgeSteps; i++) {
      add(Offset.lerp(from, to, i / edgeSteps)!, inward);
    }
  }

  // Clockwise from the top-left corner.
  addArc(Offset(radius, radius), math.pi);
  addEdge(Offset(radius, 0), Offset(width - radius, 0), const Offset(0, 1));
  addArc(Offset(width - radius, radius), math.pi * 1.5);
  addEdge(
    Offset(width, radius),
    Offset(width, height - radius),
    const Offset(-1, 0),
  );
  addArc(Offset(width - radius, height - radius), 0);
  addEdge(
    Offset(width - radius, height),
    Offset(radius, height),
    const Offset(0, -1),
  );
  addArc(Offset(radius, height - radius), math.pi * 0.5);
  addEdge(Offset(0, height - radius), Offset(0, radius), const Offset(1, 0));

  final path = Path();
  final start = (points.first + points[1]) / 2;
  path.moveTo(start.dx, start.dy);
  for (var i = 1; i <= points.length; i++) {
    final current = points[i % points.length];
    final next = points[(i + 1) % points.length];
    final mid = (current + next) / 2;
    path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
  }
  path.close();
  return path;
}
