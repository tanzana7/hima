import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Geometry shared by the paint primitives.
///
/// Every shape in the kit is built from a seed instead of a random number
/// drawn at paint time. A card therefore keeps its exact silhouette across
/// rebuilds, foreground polls and scrolling, and the same friend always gets
/// the same splash. The generated paths are cached per (seed, size, config) so
/// a scrolling list does not re-sample an outline on every frame.

/// A stable seed for a name, id or section label.
///
/// `String.hashCode` is only required to be consistent inside one process, so
/// it would give a card a different shape after a restart. FNV-1a over the code
/// units is a few operations and never changes.
int paintSeedOf(Object value) {
  var hash = 0x811c9dc5;
  for (final unit in value.toString().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// A tiny bounded cache for generated geometry.
///
/// The home screen shows a dozen cards; a Map keyed on the shape inputs keeps
/// the outline sampling out of the paint pass entirely. When the cache fills it
/// is dropped wholesale: the shapes are cheap to rebuild and a real LRU would
/// cost more than it saves at this size.
class PaintCache<T> {
  PaintCache({this.capacity = 192});

  final int capacity;
  final Map<Object, T> _entries = {};

  T get(Object key, T Function() build) {
    final hit = _entries[key];
    if (hit != null) return hit;
    final value = build();
    if (_entries.length >= capacity) _entries.clear();
    _entries[key] = value;
    return value;
  }
}

/// A lighter or darker tone of [base], used for the tonal variation inside a
/// splash and for the pooling edge of a wash.
///
/// Paint is never one flat value: a single-colour fill reads as a vector shape
/// however irregular its outline is.
Color paintTone(Color base, double amount) {
  final target = amount < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  return Color.lerp(base, target, amount.abs().clamp(0.0, 1.0)) ?? base;
}

/// One satellite droplet thrown off a splash.
class PaintDroplet {
  const PaintDroplet({
    required this.center,
    required this.radius,
    this.neckFrom,
    this.neckWidth = 1.6,
  });

  final Offset center;
  final double radius;

  /// Where the thin neck joins the main blob, when this droplet has one. The
  /// neck is what reads as a splash instead of a scatter of dots.
  final Offset? neckFrom;
  final double neckWidth;
}

/// A tongue of paint hanging off the bottom edge, ending in a round bead.
class PaintDrip {
  const PaintDrip({
    required this.start,
    required this.end,
    required this.width,
    required this.bead,
  });

  final Offset start;
  final Offset end;
  final double width;
  final double bead;
}

/// A splash silhouette plus its droplets and drips.
class PaintBlob {
  const PaintBlob({
    required this.path,
    required this.center,
    required this.droplets,
    required this.drips,
  });

  final Path path;
  final Offset center;
  final List<PaintDroplet> droplets;
  final List<PaintDrip> drips;
}

final _blobCache = PaintCache<PaintBlob>();
final _brushCache = PaintCache<Path>();
final _swashCache = PaintCache<Path>();

/// Builds (or returns the cached) splash for one box.
///
/// The outline is a rounded rectangle expressed in polar coordinates: for every
/// angle the radius is the distance from the centre to the rounded-rectangle
/// edge, multiplied by a sum of two to four sine harmonics with seeded phases.
/// Polar form is what keeps the edge continuous — there is no list of corner
/// points to show through — and the harmonics give the slow lobes and the fine
/// ripples that read as paint rather than as a vector shape.
///
/// The wobble only ever pushes the outline *outward*, so the padded content
/// rect is always inside the paint however the harmonics land.
PaintBlob paintBlob({
  required Size size,
  required int seed,
  required EdgeInsets padding,
  required double corner,
  required double wobble,
  required int dropletCount,
  required int dripCount,
  double grow = 1,
  int lobes = 0,
  bool circleBase = false,
}) {
  final key = (
    size,
    seed,
    padding,
    corner,
    wobble,
    dropletCount,
    dripCount,
    grow,
    lobes,
    circleBase,
  );
  return _blobCache.get(
    key,
    () => _buildBlob(
      size: size,
      seed: seed,
      padding: padding,
      corner: corner,
      wobble: wobble,
      dropletCount: dropletCount,
      dripCount: dripCount,
      grow: grow,
      lobes: lobes,
      circleBase: circleBase,
    ),
  );
}

PaintBlob _buildBlob({
  required Size size,
  required int seed,
  required EdgeInsets padding,
  required double corner,
  required double wobble,
  required int dropletCount,
  required int dripCount,
  required double grow,
  required int lobes,
  required bool circleBase,
}) {
  final rng = math.Random(seed);
  final halfW = size.width / 2;
  final halfH = size.height / 2;
  final center = Offset(halfW, halfH);
  // A circle base is for the small lobed marks, which carry no content and so
  // do not have to keep a safe rect.
  final rc = circleBase
      ? math.min(halfW, halfH)
      : paintCornerRadius(halfW, halfH, padding, corner);
  final amplitude = wobble.clamp(0.0, 0.5);

  // A lobed mark (the star dab) uses one strong harmonic; a splash uses two to
  // four so no two cards share a silhouette.
  //
  // The frequencies must be integers. The wobble is a function of the angle
  // returned by `atan2`, which wraps from +π to -π across the left edge; a
  // fractional frequency is not periodic over that wrap, so the radius would
  // jump there and leave a visible seam in the outline.
  final count = lobes > 0 ? 1 : 2 + rng.nextInt(3);
  final phases = <double>[];
  final freqs = <double>[];
  final amps = <double>[];
  for (var i = 0; i < count; i++) {
    phases.add(rng.nextDouble() * math.pi * 2);
    freqs.add(
      lobes > 0 ? lobes.toDouble() : (2 + i * 2 + rng.nextInt(2)).toDouble(),
    );
    amps.add(lobes > 0 ? 1.0 : 0.45 + rng.nextDouble() * 0.55);
  }
  final ampSum = amps.fold(0.0, (sum, value) => sum + value);

  // The base outline is the rounded rectangle sampled evenly along its
  // perimeter, and each sample is then pushed out along its own radius. A polar
  // formula `r = a / cos θ` is only correct for a plain rectangle and collapses
  // into a lens once the corner radius is folded in; walking the perimeter keeps
  // the shape exact, which is what makes the padded content rect safe.
  const steps = 120;
  final perimeter = _roundedRectPerimeter(halfW, halfH, rc, steps);
  // Normalised so the largest radius stays inside the box: the paint never
  // spills past its own box, so a card can never paint over its neighbour.
  // [grow] is the one deliberate exception, used to lay the declared hero's
  // splash over the idle one.
  final normalise = 1 + amplitude;
  final points = <Offset>[];
  for (final point in perimeter) {
    // The perimeter is generated around the origin, so it is already relative
    // to the shape's centre: scaling it scales about that centre.
    final distance = point.distance;
    if (distance <= 0) continue;
    final theta = math.atan2(point.dy, point.dx);
    var h = 0.0;
    for (var k = 0; k < count; k++) {
      h += amps[k] * (0.5 + 0.5 * math.sin(freqs[k] * theta + phases[k]));
    }
    h /= ampSum;
    // The 0.35 floor keeps a minimum outward push even where every harmonic
    // happens to be low, which covers the tiny loss from smoothing.
    final factor = ((1 + amplitude * (0.35 + 0.65 * h)) / normalise) * grow;
    points.add(center + point * factor);
  }

  final droplets = <PaintDroplet>[];
  // Droplets scale with the box and are clamped: on a 48dp chip an absolute
  // 12dp droplet would land on the next chip, and on a 300dp hero a relative
  // one would be invisible.
  final unit = math.min(size.width, size.height);
  for (var i = 0; i < dropletCount; i++) {
    final edge = points[rng.nextInt(points.length)];
    final outward = edge - center;
    final distance = outward.distance;
    if (distance <= 0) continue;
    final direction = outward / distance;
    final gap = (unit * (0.02 + rng.nextDouble() * 0.05)).clamp(2.0, 7.0);
    final radius = (unit * (0.012 + rng.nextDouble() * 0.02)).clamp(1.4, 4.0);
    // Roughly half the droplets keep a neck back to the blob; the rest are
    // flung clear, which is what a real splash looks like.
    final connected = rng.nextDouble() < 0.5;
    droplets.add(
      PaintDroplet(
        center: edge + direction * (gap + radius),
        radius: radius,
        neckFrom: connected ? edge - direction * 1.5 : null,
        neckWidth: 1.0 + rng.nextDouble() * 1.4,
      ),
    );
  }

  // Drips hang off the bottom edge only: paint runs down, it does not climb.
  final bottom = points
      .where((point) => point.dy > center.dy + halfH * 0.55)
      .toList();
  final drips = <PaintDrip>[];
  for (var i = 0; i < dripCount && bottom.isNotEmpty; i++) {
    final edge = bottom[rng.nextInt(bottom.length)];
    final length = 6 + rng.nextDouble() * 6;
    drips.add(
      PaintDrip(
        start: edge - const Offset(0, 1.5),
        end: Offset(edge.dx + (rng.nextDouble() - 0.5) * 5, edge.dy + length),
        width: 1.8 + rng.nextDouble() * 2.2,
        bead: 1.8 + rng.nextDouble() * 1.8,
      ),
    );
  }

  return PaintBlob(
    path: smoothClosedPath(points),
    center: center,
    droplets: droplets,
    drips: drips,
  );
}

/// The largest corner radius whose rounded rectangle still contains the rect
/// inset by [padding].
///
/// A rounded rectangle loses its corners, and the padded content rect has to
/// stay inside the paint. Solving `(rc - padV)² + (rc - padH)² ≤ rc²` gives the
/// ceiling, so a caller can ask for a pill and get the roundest corner the
/// padding allows instead of a shape that cuts into its own label.
double paintCornerRadius(
  double halfW,
  double halfH,
  EdgeInsets padding,
  double requested,
) {
  final padV = math.max(padding.top, padding.bottom);
  final padH = math.max(padding.left, padding.right);
  final sum = padV + padH;
  final limit =
      sum + math.sqrt(math.max(0, sum * sum - (padV * padV + padH * padH)));
  return math.min(math.min(halfW, halfH) * 0.92, math.min(requested, limit));
}

/// Points evenly spaced along the perimeter of a rounded rectangle centred on
/// the origin.
///
/// Spacing is by arc length rather than by angle, so the smoothing below gets
/// the same sample density on a long edge and on a small corner arc. Sampling
/// by angle would bunch samples at the corners of a wide, short box and leave
/// the long edges nearly straight.
List<Offset> _roundedRectPerimeter(
  double halfW,
  double halfH,
  double rc,
  int steps,
) {
  final ax = math.max(0.0, halfW - rc);
  final ay = math.max(0.0, halfH - rc);
  final arc = math.pi * rc / 2;
  final segments = <(double, Offset Function(double))>[
    // Top edge, left to right.
    (2 * ax, (t) => Offset(-ax + 2 * ax * t, -halfH)),
    // Top-right corner arc.
    (
      arc,
      (t) => Offset(
        ax + rc * math.sin(t * math.pi / 2),
        -ay - rc * math.cos(t * math.pi / 2),
      ),
    ),
    // Right edge, top to bottom.
    (2 * ay, (t) => Offset(halfW, -ay + 2 * ay * t)),
    // Bottom-right corner arc.
    (
      arc,
      (t) => Offset(
        ax + rc * math.cos(t * math.pi / 2),
        ay + rc * math.sin(t * math.pi / 2),
      ),
    ),
    // Bottom edge, right to left.
    (2 * ax, (t) => Offset(ax - 2 * ax * t, halfH)),
    // Bottom-left corner arc.
    (
      arc,
      (t) => Offset(
        -ax - rc * math.sin(t * math.pi / 2),
        ay + rc * math.cos(t * math.pi / 2),
      ),
    ),
    // Left edge, bottom to top.
    (2 * ay, (t) => Offset(-halfW, ay - 2 * ay * t)),
    // Top-left corner arc.
    (
      arc,
      (t) => Offset(
        -ax - rc * math.cos(t * math.pi / 2),
        -ay - rc * math.sin(t * math.pi / 2),
      ),
    ),
  ];
  final total = segments.fold(0.0, (sum, segment) => sum + segment.$1);
  if (total <= 0) return const [];
  final points = <Offset>[];
  for (var i = 0; i < steps; i++) {
    var remaining = total * i / steps;
    for (final (length, at) in segments) {
      if (length <= 0) continue;
      if (remaining <= length) {
        points.add(at(remaining / length));
        break;
      }
      remaining -= length;
    }
  }
  return points;
}

/// Joins sampled points with quadratics through their midpoints.
///
/// Every sample becomes a control point and every midpoint an on-curve point,
/// so the result is C1 continuous: no polygon corner can show through, which is
/// the difference between a splash and a starburst.
Path smoothClosedPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  final count = points.length;
  final start = (points[count - 1] + points[0]) / 2;
  path.moveTo(start.dx, start.dy);
  for (var i = 0; i < count; i++) {
    final current = points[i];
    final next = points[(i + 1) % count];
    final mid = (current + next) / 2;
    path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
  }
  path.close();
  return path;
}

/// A hand-painted underline: thick through the middle, tapering to nothing at
/// both ends, with a ragged edge and a slow drift so it does not read as a
/// rule.
Path paintBrushPath({
  required Size size,
  required int seed,
}) {
  return _brushCache.get((size, seed), () => _buildBrushPath(size, seed));
}

Path _buildBrushPath(Size size, int seed) {
  final rng = math.Random(seed);
  const steps = 30;
  final height = math.max(1.0, size.height);
  final drift = (rng.nextDouble() - 0.5) * height * 0.35;
  final top = <Offset>[];
  final bottom = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    // Taper: a sine envelope is thick in the middle and vanishes at the ends,
    // which is how a loaded brush leaves the paper.
    final taper = math.pow(math.sin(math.pi * t), 0.55).toDouble();
    final ragged = 0.82 + rng.nextDouble() * 0.36;
    final half = height * 0.5 * taper * ragged;
    final midY = height * 0.5 + drift * (t - 0.5) * 2;
    top.add(Offset(t * size.width, midY - half));
    bottom.add(Offset(t * size.width, midY + half));
  }
  final path = Path()..moveTo(top.first.dx, top.first.dy);
  for (var i = 1; i < top.length; i++) {
    final previous = top[i - 1];
    final current = top[i];
    final mid = (previous + current) / 2;
    path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
  }
  path.lineTo(top.last.dx, top.last.dy);
  path.lineTo(bottom.last.dx, bottom.last.dy);
  for (var i = bottom.length - 2; i >= 0; i--) {
    final previous = bottom[i + 1];
    final current = bottom[i];
    final mid = (previous + current) / 2;
    path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
  }
  path.lineTo(bottom.first.dx, bottom.first.dy);
  path.close();
  return path;
}

/// The irregular top edge of the bottom-navigation swash.
///
/// The wash spans the full width and runs off the bottom of the box, so only
/// its top edge is visible: a horizontal wobble that never reaches the straight
/// line a Material bar would draw.
Path paintSwashPath({
  required Size size,
  required int seed,
  required double top,
  required double wobble,
}) {
  return _swashCache.get((size, seed, top, wobble), () {
    final rng = math.Random(seed);
    final phaseA = rng.nextDouble() * math.pi * 2;
    final phaseB = rng.nextDouble() * math.pi * 2;
    final freqA = 1.6 + rng.nextDouble() * 1.2;
    final freqB = 3.4 + rng.nextDouble() * 1.8;
    const steps = 48;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final y =
          top +
          wobble *
              (0.55 * math.sin(freqA * math.pi * 2 * t + phaseA) +
                  0.45 * math.sin(freqB * math.pi * 2 * t + phaseB));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(size.width + 2, size.height + 2);
    path.lineTo(-2, size.height + 2);
    path.close();
    return path;
  });
}
