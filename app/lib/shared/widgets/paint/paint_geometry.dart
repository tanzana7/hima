import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Geometry shared by the paint primitives.
///
/// Every shape in the kit is built from a seed instead of a random number
/// drawn at paint time. A card therefore keeps its exact silhouette across
/// rebuilds, foreground polls and scrolling, and the same friend always gets
/// the same splash. The generated paths are cached per (seed, size, config) so
/// a scrolling list does not re-sample an outline on every frame.
///
/// **Anatomy of a swipe.** A wide band painted with one sideways movement: a
/// blunt loaded start, a band whose edges wobble, an end that breaks into
/// uneven fingers with rounded tips, and the splatter flicked off it. It is the
/// opposite of a splash — nothing grows out of it — and it is the only
/// primitive that keeps its whole silhouette inside the box width. See
/// [paintSwipe].
///
/// **Anatomy of a splash.** A body, arms and droplets:
///
/// * The **body** is a rounded-rectangle centre line with four uneven corner
///   radii, displaced by a low-frequency wobble of 4–10% of the short side, so
///   no side stays straight and no two corners match.
/// * The **arms** are tapered lobes that shoot out of the body edge and end in
///   a round tip, sometimes with a bead. They are filled shapes joined to the
///   body, never strokes and never thin necks.
/// * The **droplets** are detached, of two sizes, clustered along the direction
///   of an arm and getting smaller with distance.
///
/// Nothing here draws a line: a splash that is outlined or joined by a stroke
/// reads as a vector icon, which is exactly what the paint look replaces.

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

/// One arm of a splash: a tapered lobe that shoots out of the body edge.
///
/// The lobe is wide where it joins the body and narrows to a round tip, which
/// is how a thrown splash of paint spreads. It is a filled shape that overlaps
/// the body, so the join has no seam and there is no stroked outline anywhere.
class PaintArm {
  const PaintArm({
    required this.path,
    required this.base,
    required this.tip,
    required this.direction,
    required this.bead,
  });

  /// The filled lobe, in the same coordinates as [PaintBlob.path].
  final Path path;

  /// The point on the body edge the lobe grows out of.
  final Offset base;

  /// The centre of the round tip.
  final Offset tip;

  /// Unit vector from [base] to [tip]. The painter scales along this axis to
  /// make the arm shoot out during the splash.
  final Offset direction;

  /// Radius of the bead sitting on the tip, or 0 when the tip is plain.
  final double bead;
}

/// One satellite droplet thrown off a splash.
class PaintDroplet {
  const PaintDroplet({
    required this.center,
    required this.radius,
    this.direction = Offset.zero,
    this.stretch = 0,
  });

  final Offset center;
  final double radius;

  /// Direction the droplet was travelling in. Only used together with
  /// [stretch]; a droplet is never connected back to the body by a neck.
  final Offset direction;

  /// 0 paints a circle, 1 an egg stretched along [direction]. The big droplets
  /// are slightly stretched because a fast drop is not a perfect sphere, but
  /// the shape stays a filled blob: no tail, no line.
  final double stretch;
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

/// A splash silhouette plus its arms, droplets and drips.
class PaintBlob {
  const PaintBlob({
    required this.path,
    required this.center,
    required this.arms,
    required this.droplets,
    required this.drips,
  });

  final Path path;
  final Offset center;
  final List<PaintArm> arms;
  final List<PaintDroplet> droplets;
  final List<PaintDrip> drips;
}

final _blobCache = PaintCache<PaintBlob>();
final _silhouetteCache = PaintCache<Path>();
final _brushCache = PaintCache<Path>();
final _swashCache = PaintCache<Path>();

/// The furthest any splash reaches past its own box, in dp.
///
/// The wobble, the arms, the beads and the droplets are all capped so that this
/// is a hard bound rather than a typical value: a caller that wants the paint
/// to land on paper instead of on the widget below reserves exactly this much
/// and does not have to measure the shape. The home screen uses it as the gap
/// around the hero.
///
/// The bound holds for the *painted* result: [paintBlob]'s `grow` scales the
/// whole splash about its centre after it is built, and a stretched droplet is
/// an egg rather than a circle, so both are folded into the clamp instead of
/// being applied on top of it.
const double paintMaxBleed = 40;

/// How the [paintMaxBleed] budget is spent: the edge wobble takes the first
/// slice, the bead on an arm tip the last, and the arms get what is left.
const double _bleedWobble = 12;
const double _bleedBead = 7;

/// Builds (or returns the cached) splash for one box.
///
/// **Geometry.** The body starts from a rounded-rectangle *centre line* with a
/// different radius on each corner, sampled evenly along its perimeter. Every
/// sample is then displaced along its own radius by a sum of two or three low
/// harmonics of the arc length (seeded phase and amplitude). Because the
/// harmonics are periodic over the perimeter the outline closes without a seam,
/// and because they are low frequency the edge bulges and dents in big slow
/// lobes instead of turning into noise.
///
/// The displacement is measured against the *short side* rather than against
/// the radius: on a wide card a radius-relative wobble is invisible along the
/// long edges, which is how the first version ended up looking like a rounded
/// rectangle.
///
/// **Content safety.** The inward half of the wobble is clamped to the padded
/// content rect, so however the harmonics land the label is always on paint.
/// The outward half is free to leave the widget box: the caller gives the paint
/// room (a `Stack` with `Clip.none`, a gap in the layout) rather than the
/// geometry shrinking the wobble until it disappears.
///
/// [arms] is the number of lobes; null picks 3–7 from the seed, 0 draws none.
/// [armLength] is the lobe length as a fraction of the short side.
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
  int? arms,
  double armLength = 0.16,
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
    arms,
    armLength,
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
      arms: arms,
      armLength: armLength,
    ),
  );
}

/// The body and its arms unioned into a single path.
///
/// A wash is translucent, so drawing the arms as separate overlapping shapes
/// would show every join as a darker patch. The union keeps one layer one flat
/// value, which is what a wet wash looks like. The result is cached like the
/// blob itself.
Path paintSilhouette({
  required Size size,
  required int seed,
  required EdgeInsets padding,
  required double corner,
  required double wobble,
  double grow = 1,
  int? arms,
  double armLength = 0.16,
}) {
  final key = (size, seed, padding, corner, wobble, grow, arms, armLength);
  return _silhouetteCache.get(key, () {
    final blob = paintBlob(
      size: size,
      seed: seed,
      padding: padding,
      corner: corner,
      wobble: wobble,
      dropletCount: 0,
      dripCount: 0,
      grow: grow,
      arms: arms,
      armLength: armLength,
    );
    var path = blob.path;
    for (final arm in blob.arms) {
      path = Path.combine(PathOperation.union, path, arm.path);
    }
    return path;
  });
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
  required int? arms,
  required double armLength,
}) {
  final rng = math.Random(seed);
  final halfW = size.width / 2;
  final halfH = size.height / 2;
  final center = Offset(halfW, halfH);
  final shortSide = math.min(size.width, size.height);
  // 4–10% of the short side is what reads as paint at arm's length; below that
  // the edge still looks ruled, above it the shape turns into a star. The
  // absolute cap keeps the outline inside the [paintMaxBleed] budget on a very
  // large box, where a percentage would spill far past the widget.
  final amplitude = math.min(
    wobble.clamp(0.0, 0.14) * shortSide,
    _bleedWobble,
  );

  final outline = lobes > 0
      ? _starOutline(shortSide, lobes, wobble, rng)
      : _bodyOutline(
          halfW: halfW,
          halfH: halfH,
          padding: padding,
          corner: corner,
          circleBase: circleBase,
          amplitude: amplitude,
          rng: rng,
        );
  final points = [for (final point in outline) center + point];

  final builtArms = <PaintArm>[];
  final armCount = arms ?? (lobes > 0 ? 0 : 3 + rng.nextInt(5));
  if (armCount > 0 && points.length > 8) {
    _buildArms(
      into: builtArms,
      points: points,
      center: center,
      shortSide: shortSide,
      grow: grow,
      count: armCount,
      lengthFraction: armLength,
      rng: rng,
    );
  }

  final droplets = _buildDroplets(
    points: points,
    center: center,
    shortSide: shortSide,
    grow: grow,
    arms: builtArms,
    count: dropletCount,
    rng: rng,
  );

  final drips = _buildDrips(
    points: points,
    center: center,
    halfH: halfH,
    grow: grow,
    count: dripCount,
    rng: rng,
  );

  return _scaled(
    PaintBlob(
      path: smoothClosedPath(points),
      center: center,
      arms: builtArms,
      droplets: droplets,
      drips: drips,
    ),
    center,
    grow,
  );
}

/// The body outline, relative to the centre of the box.
///
/// A rounded rectangle with four different corner radii is already not a
/// rectangle: one corner stays fat and round while the opposite one is pinched
/// almost square. The wobble on top of that is what removes the straight sides.
List<Offset> _bodyOutline({
  required double halfW,
  required double halfH,
  required EdgeInsets padding,
  required double corner,
  required bool circleBase,
  required double amplitude,
  required math.Random rng,
}) {
  final cap = circleBase
      ? math.min(halfW, halfH)
      : paintCornerRadius(halfW, halfH, padding, corner);
  // A smaller radius only ever moves the outline further out, so the padded
  // content rect stays inside every corner however the radii land.
  final radii = circleBase
      ? [cap, cap, cap, cap]
      : [for (var i = 0; i < 4; i++) cap * (0.55 + 0.45 * rng.nextDouble())];

  final perimeter = _roundedRectPerimeter(halfW, halfH, radii);
  final steps = perimeter.length;
  if (steps == 0) return const [];

  // Two or three harmonics of the arc length. The frequencies must be integers:
  // the wobble is a function of the position along the perimeter, which wraps
  // from the last sample back to the first, and a fractional frequency would
  // not close and would leave a step in the outline.
  final count = 2 + rng.nextInt(2);
  final freqs = <double>[];
  final phases = <double>[];
  final amps = <double>[];
  for (var i = 0; i < count; i++) {
    freqs.add((3 + i * 2 + rng.nextInt(2)).toDouble());
    phases.add(rng.nextDouble() * math.pi * 2);
    amps.add(0.5 + rng.nextDouble() * 0.5);
  }
  final ampSum = amps.fold(0.0, (sum, value) => sum + value);

  final points = <Offset>[];
  for (var i = 0; i < steps; i++) {
    final point = perimeter[i];
    final distance = point.distance;
    if (distance <= 0) continue;
    final s = i / steps;
    var h = 0.0;
    for (var k = 0; k < count; k++) {
      h += amps[k] * math.sin(2 * math.pi * freqs[k] * s + phases[k]);
    }
    h /= ampSum;
    final direction = point / distance;
    // The floor keeps the padded content rect covered even where every
    // harmonic happens to pull inward at once.
    final floor =
        _safeRadius(math.atan2(point.dy, point.dx), halfW, halfH, padding) +
        0.75;
    points.add(direction * math.max(floor, distance + amplitude * h));
  }
  return points;
}

/// A lobed mark (the star): a circle whose radius is modulated by one harmonic.
///
/// It carries no content, so it does not need a safe rect and can spend the
/// whole box on the lobed silhouette.
List<Offset> _starOutline(
  double shortSide,
  int lobes,
  double wobble,
  math.Random rng,
) {
  const steps = 96;
  final radius = shortSide / 2;
  final phase = rng.nextDouble() * math.pi * 2;
  final amount = wobble.clamp(0.0, 0.6);
  final points = <Offset>[];
  for (var i = 0; i < steps; i++) {
    final theta = 2 * math.pi * i / steps;
    final r = radius * (1 + amount * math.sin(lobes * theta + phase)) /
        (1 + amount);
    points.add(Offset(math.cos(theta) * r, math.sin(theta) * r));
  }
  return points;
}

/// Adds [count] tapered lobes around the body edge.
///
/// The arms are spread around the perimeter with a seeded jitter rather than
/// evenly: an even ring of arms reads as a gear, an uneven one as a splash.
///
/// Each arm is capped so that, after [grow] has scaled it about the centre, its
/// tip plus the bead on it still lands inside [paintMaxBleed] of the box edge.
void _buildArms({
  required List<PaintArm> into,
  required List<Offset> points,
  required Offset center,
  required double shortSide,
  required double grow,
  required int count,
  required double lengthFraction,
  required math.Random rng,
}) {
  final n = points.length;
  final step = n / count;
  for (var i = 0; i < count; i++) {
    final index =
        (step * i + step * 0.5 * (rng.nextDouble() - 0.5)).round() % n;
    final base = points[index];
    final previous = points[(index - 2 + n) % n];
    final next = points[(index + 2) % n];
    final raw = next - previous;
    if (raw.distance < 0.01) continue;
    final tangent = raw / raw.distance;
    var normal = Offset(-tangent.dy, tangent.dx);
    // Point the lobe away from the centre, whichever way the tangent ran.
    if (normal.dx * (base.dx - center.dx) + normal.dy * (base.dy - center.dy) <
        0) {
      normal = -normal;
    }

    // The tip sits `length` past the base along the edge normal, and the base
    // is already out on the wobbled outline, so the room left for the lobe is
    // measured from where this arm actually starts.
    final maxLength = _maxArmLength(base, normal, center, grow);
    final length = math.min(
      lengthFraction * shortSide * (0.8 + 0.4 * rng.nextDouble()),
      maxLength,
    );
    if (length < 1.5) continue;
    // A fat base and a narrow tip is what makes the lobe read as paint spread
    // by an impact; a constant-width lobe reads as a spoke. The base has to be
    // a large fraction of the length, because the widest part sits inside the
    // body and only the tapered outer half is visible.
    final halfBase = math.max(2.2, length * (0.45 + 0.25 * rng.nextDouble()));
    final tipRadius = math.max(
      1.4,
      halfBase * (0.45 + 0.25 * rng.nextDouble()),
    );
    // The lobe starts inside the body so the join is a fill-over-fill overlap
    // with no seam to trace. It is kept short: a deep overlap hides most of the
    // taper and leaves a spike.
    final overlap = math.min(halfBase * 0.55, 7.0);
    final bead = rng.nextDouble() < 0.45
        ? math.min(tipRadius * (1.15 + 0.5 * rng.nextDouble()), _bleedBead)
        : 0.0;
    into.add(
      PaintArm(
        path: smoothClosedPath(
          _armPoints(
            base,
            normal,
            tangent,
            length,
            halfBase,
            tipRadius,
            overlap,
          ),
        ),
        base: base,
        tip: base + normal * length,
        direction: normal,
        bead: bead,
      ),
    );
  }
}

/// The point ring of one arm, in the local frame of its base point.
///
/// The two sides are the same taper mirrored, and the tip is a half circle, so
/// the lobe is a filled teardrop: wide at the body, round at the end.
List<Offset> _armPoints(
  Offset base,
  Offset direction,
  Offset tangent,
  double length,
  double halfBase,
  double tipRadius,
  double overlap,
) {
  const side = 9;
  const cap = 7;
  final spine = overlap + length - tipRadius;
  final capCenter = base + direction * (length - tipRadius);
  final points = <Offset>[];
  for (var i = 0; i <= side; i++) {
    final s = i / side;
    final width =
        tipRadius + (halfBase - tipRadius) * math.pow(1 - s, 0.7).toDouble();
    points.add(base + direction * (-overlap + spine * s) + tangent * width);
  }
  for (var i = 1; i < cap; i++) {
    final phi = math.pi * i / cap;
    points.add(
      capCenter +
          tangent * (tipRadius * math.cos(phi)) +
          direction * (tipRadius * math.sin(phi)),
    );
  }
  for (var i = side; i >= 0; i--) {
    final s = i / side;
    final width =
        tipRadius + (halfBase - tipRadius) * math.pow(1 - s, 0.7).toDouble();
    points.add(base + direction * (-overlap + spine * s) - tangent * width);
  }
  return points;
}

/// Detached droplets, clustered along the arms and getting smaller with
/// distance.
///
/// A droplet is never joined to the body: the thin neck the first version drew
/// from the edge to each drop was a straight line, which is the one thing the
/// paint look has to avoid.
///
/// Every droplet is pulled back to the [paintMaxBleed] budget, so a droplet on
/// a long arm cannot end up further out than the room the caller reserved.
List<PaintDroplet> _buildDroplets({
  required List<Offset> points,
  required Offset center,
  required double shortSide,
  required double grow,
  required List<PaintArm> arms,
  required int count,
  required math.Random rng,
}) {
  if (count <= 0) return const [];
  final big = (shortSide * 0.030).clamp(2.4, 7.0);
  final small = (shortSide * 0.012).clamp(1.0, 2.6);
  final clustered = arms.isEmpty ? 0 : (count * 0.75).ceil();
  final droplets = <PaintDroplet>[];

  for (var i = 0; i < count; i++) {
    if (i < clustered) {
      final arm = arms[i % arms.length];
      final rank = i ~/ arms.length;
      final radius = rank == 0 ? big * (0.8 + 0.2 * rng.nextDouble()) : small;
      final gap = shortSide * (0.02 + 0.03 * rng.nextDouble()) * (rank + 1);
      final lateral =
          (rng.nextDouble() - 0.5) * (radius * 2.4 + shortSide * 0.03);
      final tangent = Offset(-arm.direction.dy, arm.direction.dx);
      // Only the big first drops are stretched; a stretched dot on the far end
      // of the cluster reads as a smear. The stretch still counts towards the
      // painted extent, so the clamp uses the egg's long axis.
      final stretch = rank == 0 ? 0.22 : 0.0;
      droplets.add(
        PaintDroplet(
          center: _clampToBleed(
            arm.tip + arm.direction * (gap + radius) + tangent * lateral,
            center,
            radius * (1 + stretch),
            grow,
          ),
          radius: radius,
          direction: arm.direction,
          stretch: stretch,
        ),
      );
      continue;
    }
    final edge = points[rng.nextInt(points.length)];
    final outward = edge - center;
    final distance = outward.distance;
    if (distance <= 0) continue;
    final direction = outward / distance;
    final radius = small * (0.7 + 0.5 * rng.nextDouble());
    final gap = shortSide * (0.015 + 0.035 * rng.nextDouble());
    droplets.add(
      PaintDroplet(
        center: _clampToBleed(
          edge + direction * (gap + radius),
          center,
          radius,
          grow,
        ),
        radius: radius,
        direction: direction,
      ),
    );
  }
  return droplets;
}

/// The longest arm that keeps its tip, plus the bead on it, inside the
/// [paintMaxBleed] budget.
///
/// The budget is measured along the direction the tip ends up in, and that
/// direction depends on the length, so this solves it in two passes: the first
/// uses the edge normal, the second the direction the first tip actually
/// landed in. The two differ by a fraction of a degree, but on a wide box that
/// is enough for the tip to slip past the budget by a dp if it is not
/// corrected.
double _maxArmLength(
  Offset base,
  Offset normal,
  Offset center,
  double grow,
) {
  final offset = base - center;
  final rBase = offset.distance;
  var length =
      _bleedLimit(_boxRadius(normal, center), grow) - rBase - _bleedBead;
  if (length <= 0) return length;
  final tip = offset + normal * length;
  final rTip = tip.distance;
  if (rTip > 0) {
    length = _bleedLimit(_boxRadius(tip / rTip, center), grow) -
        rBase -
        _bleedBead;
  }
  return length;
}

/// The distance from the centre of the box to its edge along [direction].
double _boxRadius(Offset direction, Offset center) {
  final dx = direction.dx.abs();
  final dy = direction.dy.abs();
  final rx = dx <= 1e-6 ? double.infinity : center.dx / dx;
  final ry = dy <= 1e-6 ? double.infinity : center.dy / dy;
  return math.min(rx, ry);
}

/// How far from the centre an outward element may sit, given the box radius
/// along its direction and the [grow] the whole splash is scaled by afterwards.
///
/// A point at distance `d` is painted at `d * grow`, and the box does not grow
/// with it, so the budget has to be solved in the scaled world:
/// `(d * grow) - boxRadius <= paintMaxBleed`.
double _bleedLimit(double boxRadius, double grow) =>
    (paintMaxBleed + boxRadius) / grow;

/// Pulls [point] back until the shape of [radius] around it stays inside the
/// [paintMaxBleed] budget once the splash has been scaled by [grow].
///
/// [radius] is the element's own painted extent, not just its nominal radius: a
/// stretched droplet is an egg whose long axis is `radius * (1 + stretch)`, so
/// passing the plain radius would let its tip out of the budget.
Offset _clampToBleed(
  Offset point,
  Offset center,
  double radius,
  double grow,
) {
  final delta = point - center;
  final distance = delta.distance;
  if (distance <= 0) return point;
  final direction = delta / distance;
  final limit = _bleedLimit(_boxRadius(direction, center), grow) - radius - 1;
  if (distance <= limit) return point;
  return center + direction * limit;
}

/// Drips hang off the bottom edge only: paint runs down, it does not climb.
List<PaintDrip> _buildDrips({
  required List<Offset> points,
  required Offset center,
  required double halfH,
  required double grow,
  required int count,
  required math.Random rng,
}) {
  if (count <= 0) return const [];
  final bottom = points
      .where((point) => point.dy > center.dy + halfH * 0.55)
      .toList();
  if (bottom.isEmpty) return const [];
  final drips = <PaintDrip>[];
  for (var i = 0; i < count; i++) {
    final edge = bottom[rng.nextInt(bottom.length)];
    final length = 9 + rng.nextDouble() * 6;
    final bead = 3.6 + rng.nextDouble() * 2.4;
    drips.add(
      PaintDrip(
        // The tongue starts inside the body so its widest part is hidden and
        // the join has no seam.
        start: edge - const Offset(0, 4),
        end: _clampToBleed(
          Offset(edge.dx + (rng.nextDouble() - 0.5) * 5, edge.dy + length),
          center,
          bead,
          grow,
        ),
        // A drip is a tongue of paint, not a thread: a 2dp width with a bead
        // on the end is a pin, which is exactly the shape the splash must not
        // have.
        width: 9 + rng.nextDouble() * 4,
        bead: bead,
      ),
    );
  }
  return drips;
}

/// [grow] scales the whole splash about its centre, used to lay one splash over
/// another. Everything is scaled together so the arms and droplets keep their
/// relationship to the body.
PaintBlob _scaled(PaintBlob blob, Offset center, double grow) {
  if (grow == 1) return blob;
  final storage = Float64List(16)
    ..[0] = grow
    ..[5] = grow
    ..[10] = 1
    ..[15] = 1
    ..[12] = center.dx * (1 - grow)
    ..[13] = center.dy * (1 - grow);
  Offset scalePoint(Offset point) => center + (point - center) * grow;
  return PaintBlob(
    path: blob.path.transform(storage),
    center: center,
    arms: [
      for (final arm in blob.arms)
        PaintArm(
          path: arm.path.transform(storage),
          base: scalePoint(arm.base),
          tip: scalePoint(arm.tip),
          direction: arm.direction,
          bead: arm.bead * grow,
        ),
    ],
    droplets: [
      for (final droplet in blob.droplets)
        PaintDroplet(
          center: scalePoint(droplet.center),
          radius: droplet.radius * grow,
          direction: droplet.direction,
          stretch: droplet.stretch,
        ),
    ],
    drips: [
      for (final drip in blob.drips)
        PaintDrip(
          start: scalePoint(drip.start),
          end: scalePoint(drip.end),
          width: drip.width * grow,
          bead: drip.bead * grow,
        ),
    ],
  );
}

/// The distance from the centre to the padded content rect along [theta].
///
/// The padded rect is star-shaped about the centre, so clamping every outline
/// sample to at least this radius is enough to keep the content on paint.
double _safeRadius(
  double theta,
  double halfW,
  double halfH,
  EdgeInsets padding,
) {
  final hw = halfW - math.max(padding.left, padding.right);
  final hh = halfH - math.max(padding.top, padding.bottom);
  if (hw <= 0 || hh <= 0) return 0;
  final cos = math.cos(theta).abs();
  final sin = math.sin(theta).abs();
  final rx = cos <= 1e-6 ? double.infinity : hw / cos;
  final ry = sin <= 1e-6 ? double.infinity : hh / sin;
  return math.min(rx, ry);
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
/// the origin, with one radius per corner.
///
/// Spacing is by arc length rather than by angle, so the smoothing below gets
/// the same sample density on a long edge and on a small corner arc. That also
/// makes the wobble — which is a function of the arc-length position — the same
/// spatial frequency everywhere, so a wide card does not end up with one slow
/// bulge along its long side and a ripple along its short one.
List<Offset> _roundedRectPerimeter(
  double halfW,
  double halfH,
  List<double> radii,
) {
  final tl = radii[0];
  final tr = radii[1];
  final br = radii[2];
  final bl = radii[3];
  final arcTl = math.pi * tl / 2;
  final arcTr = math.pi * tr / 2;
  final arcBr = math.pi * br / 2;
  final arcBl = math.pi * bl / 2;
  final top = math.max(0.0, 2 * halfW - tl - tr);
  final right = math.max(0.0, 2 * halfH - tr - br);
  final bottom = math.max(0.0, 2 * halfW - br - bl);
  final left = math.max(0.0, 2 * halfH - bl - tl);
  final total = top + right + bottom + left + arcTl + arcTr + arcBr + arcBl;
  if (total <= 0) return const [];
  // Roughly one sample every 3.5dp: enough for the harmonics and for the
  // midpoint smoothing to hide the sampling, cheap enough to cache.
  final steps = (total / 3.5).round().clamp(72, 260).toInt();

  final segments = <(double, Offset Function(double))>[
    (top, (t) => Offset(-halfW + tl + top * t, -halfH)),
    (
      arcTr,
      (t) {
        final angle = -math.pi / 2 + t * math.pi / 2;
        return Offset(
          halfW - tr + tr * math.cos(angle),
          -halfH + tr + tr * math.sin(angle),
        );
      },
    ),
    (right, (t) => Offset(halfW, -halfH + tr + right * t)),
    (
      arcBr,
      (t) {
        final angle = t * math.pi / 2;
        return Offset(
          halfW - br + br * math.cos(angle),
          halfH - br + br * math.sin(angle),
        );
      },
    ),
    (bottom, (t) => Offset(halfW - br - bottom * t, halfH)),
    (
      arcBl,
      (t) {
        final angle = math.pi / 2 + t * math.pi / 2;
        return Offset(
          -halfW + bl + bl * math.cos(angle),
          halfH - bl + bl * math.sin(angle),
        );
      },
    ),
    (left, (t) => Offset(-halfW, halfH - bl - left * t)),
    (
      arcTl,
      (t) {
        final angle = math.pi + t * math.pi / 2;
        return Offset(
          -halfW + tl + tl * math.cos(angle),
          -halfH + tl + tl * math.sin(angle),
        );
      },
    ),
  ];

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

/// The irregular top edge of a wide, shallow wash.
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
// ---------------------------------------------------------------------------
// Brush swipe
// ---------------------------------------------------------------------------

/// The paper a caller should keep around a swipe, in dp.
///
/// The fingers and the splatter stay inside the box width, but the band's edges
/// wobble a few dp past the band and a second pass over a stroke is usually
/// tilted a couple of degrees, so a caller that puts a swipe next to text
/// reserves this much. It is much smaller than [paintMaxBleed]: a stroke throws
/// its paint sideways, not in a ring.
const double paintSwipeBleed = 18;

/// The paper kept clear between the longest finger tip and the right edge of
/// the box, in dp. The splatter lands in it.
const double _swipeSplatterGap = 14;

/// The longest finger, in dp, on a box wide enough for the full stroke.
const double _swipeMaxFinger = 40;

/// The width of the dry-streak stretch at the end of the body, in dp.
const double _swipeStreakZone = 16;

/// The box width at which the stroke gets its full finger reach, in dp.
///
/// Below it the fingers, the splatter and the content inset shrink together: a
/// 40dp finger on a 200dp box would leave almost no body to paint.
const double _swipeFullWidth = 360;

/// A wide brush stroke: a blunt loaded start, a wobbling band that breaks into
/// uneven fingers, dry streaks near the end and the splatter flicked off it.
class PaintSwipe {
  const PaintSwipe({
    required this.body,
    required this.droplets,
    required this.band,
    required this.bodyRight,
    required this.tipRight,
    required this.splatterAt,
  });

  /// The whole stroke — fingers included — with the dry streaks cut out of it.
  ///
  /// The streaks are real holes: whatever is behind the stroke (paper, or the
  /// idle wash the hero paints over) shows through them instead of a
  /// paper-coloured dash being painted on top of it.
  final Path body;

  /// Individual droplets flicked off the frayed end, scattered in a cone.
  final List<PaintDroplet> droplets;

  /// The vertical extent of the band inside the box.
  final Rect band;

  /// Where the solid part of the band ends and the fingers take over.
  final double bodyRight;

  /// The furthest any finger reaches.
  final double tipRight;

  /// The reveal progress at which the brush reaches [bodyRight], so the
  /// splatter can wait for the paint instead of arriving ahead of it.
  final double splatterAt;
}

final _swipeCache = PaintCache<PaintSwipe>();

/// The scale the dry end is drawn at: 1 on a box at least [_swipeFullWidth]
/// wide, less on a narrower one.
double _swipeReach(double width) =>
    math.min(1.0, math.max(0.0, width) / _swipeFullWidth);

/// The room a swipe keeps to the right of its content, in dp.
///
/// It is the splatter gap, the longest finger and the dry-streak stretch: the
/// three things that live past the solid body. The loaded start is a fixed 4dp
/// from the left edge, so pinning the dry end to the box this way is what makes
/// the stroke read as centred in it. The old value only covered the fingers,
/// which left the paint ending about 37dp short of the right edge and the whole
/// band looking shifted left next to a full-width card below it.
///
/// It replaces the caller's `padding.right` rather than adding to it: the two
/// used to be summed, which pushed the content left of the stroke's own centre.
/// A caller that hands a child to `BrushSwipe` gets this inset for free; a
/// caller that paints a bare stroke and places the content itself (the home
/// hero, which stacks two strokes) insets by the same value so the two agree.
double paintSwipeContentInset(double width) {
  if (width <= 0) return 0;
  return _swipeSplatterGap +
      _swipeMaxFinger * _swipeReach(width) +
      _swipeStreakZone;
}

/// The part of a swipe's box painted so far, with a soft, wobbly right edge.
///
/// The painter clips the stroke with it. A caller that draws text *on* the
/// stroke clips the text with the same path, which is what lets a stroke paint
/// itself in without the text appearing ahead of the paint: the label is then
/// only ever drawn where the paint has already arrived.
///
/// The edge is seeded so it does not shimmer between frames, and it wanders by
/// a few dp so the front reads as paint rather than as a wipe.
Path paintSwipeRevealPath({
  required Size size,
  required double progress,
  required int seed,
}) {
  final t = progress.clamp(0.0, 1.0);
  final rng = math.Random(seed ^ 0x5f3a);
  final phaseA = rng.nextDouble() * math.pi * 2;
  final phaseB = rng.nextDouble() * math.pi * 2;
  final x = -2 + (size.width + 4) * t;
  const steps = 14;
  final path = Path()..moveTo(-2, -2);
  for (var i = 0; i <= steps; i++) {
    final s = i / steps;
    final wobble =
        5 * math.sin(2 * math.pi * 1.5 * s + phaseA) +
        3 * math.sin(2 * math.pi * 3.2 * s + phaseB);
    path.lineTo(x + wobble, -2 + (size.height + 4) * s);
  }
  path.lineTo(-2, size.height + 2);
  path.close();
  return path;
}

/// Builds (or returns the cached) swipe for one box.
///
/// **Geometry.** One closed Catmull-Rom spline (tension 1/6) through the
/// samples of the mock-up this stroke was drawn from, so the curve passes
/// through every sample instead of only near it: a top edge that wobbles on a
/// 41dp sine, the fingers of the dry end, a bottom edge that wobbles on a 33dp
/// sine, and a blunt rounded start.
///
/// **The dry end.** The band breaks into fingers at a fixed dp size — 8–26dp
/// thick, 1.5–4dp apart, each reaching 6–40dp past the body — so a taller band
/// gets more fingers rather than thicker ones. The count is therefore not
/// fixed: the mock-up produced about nine on a 166dp band, and a fixed count is
/// what used to read as a comb. Every finger ends in a rounded tip, never a
/// point, and the gaps cut back into the paint so the right end is never a
/// near-vertical line.
///
/// **Content safety.** The content rect is inset by [padding], and on the right
/// by [contentInset] instead of `padding.right` — the larger of the two, never
/// their sum. The body covers all of it, and the streaks, the fingers and the
/// splatter all start to its right, so no hole in the paint can run under a
/// label.
///
/// **Centring.** The loaded start sits a fixed 4dp from the left edge, so the
/// dry end is pinned to the box: the longest finger stops [_swipeSplatterGap]
/// short of the right edge and the splatter is scattered in the strip between
/// the tips and that edge. Reserving paper on the right only — which is what
/// the stroke used to do — left the paint ending well short of the right edge
/// and made the band look shifted left against the full-width cards below it.
///
/// **Fit.** Everything, splatter included, stays inside the box width. When the
/// paper right of the content is short — wide content, 200% text — the finger
/// reach and the splatter distance shrink together instead of being clipped by
/// the edge.
PaintSwipe paintSwipe({
  required Size size,
  required int seed,
  required EdgeInsets padding,
  required double contentInset,
  int? droplets,
}) {
  final key = (size, seed, padding, contentInset, droplets);
  return _swipeCache.get(
    key,
    () => _buildSwipe(
      size: size,
      seed: seed,
      padding: padding,
      contentInset: contentInset,
      dropletCount: droplets,
    ),
  );
}

PaintSwipe _buildSwipe({
  required Size size,
  required int seed,
  required EdgeInsets padding,
  required double contentInset,
  required int? dropletCount,
}) {
  final rng = math.Random(seed);
  final width = size.width;
  final height = size.height;
  if (width < 12 || height < 12) {
    return PaintSwipe(
      body: Path(),
      droplets: const [],
      band: Offset.zero & size,
      bodyRight: width,
      tipRight: width,
      splatterAt: 1,
    );
  }

  // The paper margin above and below the band. It gives the band's edge wobble
  // room to move and it is capped under the content padding so the band still
  // covers the content at every text scale.
  final bandInset = math.min(
    math.min(padding.top, padding.bottom) * 0.5,
    math.min(12.0, height * 0.08),
  );
  final band = Rect.fromLTRB(0, bandInset, width, height - bandInset);
  final top = band.top;
  final bot = band.bottom;
  final mid = (top + bot) * 0.5;
  final bandHeight = band.height;

  // The paper the band leaves between its own edge and the content edge. The
  // wobble and the jitter both spend it and neither may spend all of it: an
  // edge that dips inside the content rect puts a hole in the paint under a
  // label.
  final margin = math.max(
    0.0,
    math.min(padding.top - top, bot - (height - padding.bottom)),
  );
  // The mock-up's wobble is 5dp with ±2dp of jitter. Both are in dp rather than
  // a fraction of the band: a stroke has a direction, and a wobble that grows
  // with the band turns it into a blob.
  final wobble = math.min(5.0, math.max(0.0, margin - 2.5));
  final jitter = math.min(2.0, math.max(0.0, margin - wobble - 1.5));

  // The rect the caller lays its content out in (see [paintSwipe]). The right
  // inset is the larger of the caller's padding and the paper the dry end
  // needs, never their sum: summing them pushed the content left of the
  // stroke's own centre.
  final contentRight = math.max(
    padding.left,
    width - math.max(padding.right, contentInset),
  );
  // The dry end is pinned to the box: the longest finger stops
  // [_swipeSplatterGap] short of the right edge, so the body ends one finger
  // reach before that and the splatter lands in the strip after the tips.
  final reach = _swipeReach(width);
  final fingerReach = _swipeMaxFinger * reach;
  final bodyRight = math.max(
    contentRight,
    width - _swipeSplatterGap - fingerReach,
  );

  const x0 = 4.0;
  final topStart = math.min(x0 + 20, bodyRight);
  final points = <Offset>[];

  // The top edge, left to right: a gentle sine wobble plus a little jitter.
  for (var x = topStart; x <= bodyRight; x += 9) {
    points.add(
      Offset(x, top + math.sin(x / 41) * wobble + _jitterAt(rng, jitter)),
    );
  }

  // The dry end: the band splits into uneven fingers separated by small gaps.
  // Thickness, reach and gap are all in dp, so a taller band gets more fingers
  // instead of thicker ones.
  final fingers = <(double, double, double)>[];
  var y = top;
  while (y < bot - 4) {
    final y1 = math.min(bot, y + 8 + rng.nextDouble() * 18);
    fingers.add((y, y1, bodyRight + (6 + rng.nextDouble() * 34) * reach));
    y = y1 + 1.5 + rng.nextDouble() * 2.5;
  }
  // Each finger runs out from the body edge to a rounded tip: five samples, so
  // the spline closes it with a shoulder instead of a point.
  for (final (y0, y1, tip) in fingers) {
    final shoulder = tip - 6 * reach;
    points.add(Offset(bodyRight, y0 + 0.5));
    points.add(Offset(shoulder, y0 + (y1 - y0) * 0.25));
    points.add(Offset(tip, (y0 + y1) * 0.5));
    points.add(Offset(shoulder, y1 - (y1 - y0) * 0.25));
    points.add(Offset(bodyRight, y1 - 0.5));
  }

  // The bottom edge, right to left.
  for (var x = bodyRight; x >= topStart; x -= 9) {
    points.add(
      Offset(x, bot + math.sin(x / 33 + 1) * wobble + _jitterAt(rng, jitter)),
    );
  }

  // The loaded start: the brush touched down blunt, so the left end is a
  // rounded bulge rather than a ruled edge.
  final cap = math.min(14.0, bandHeight * 0.25);
  points.add(Offset(x0 + 6, bot - cap));
  points.add(Offset(x0 - 3, math.min(mid + 8, bot - 2)));
  points.add(Offset(x0 + 4, top + cap));

  var body = _catmullRomPath(points);

  // The dry streaks: paper-coloured slivers cut out of the last stretch of the
  // body, never under the content. The stretch is the dry-streak zone and
  // nothing more, so the paint only starts to break up where the content has
  // already ended.
  final streakStart = math.max(contentRight, bodyRight - _swipeStreakZone);
  final streakWidth = bodyRight - streakStart;
  if (streakWidth > 6 && bandHeight > 28) {
    for (var i = 0; i < 6; i++) {
      final yy = top + 12 + rng.nextDouble() * (bandHeight - 24);
      final length = streakWidth * (0.45 + 0.55 * rng.nextDouble());
      final sx = streakStart + (streakWidth - length) * rng.nextDouble();
      body = Path.combine(
        PathOperation.difference,
        body,
        _streakPath(sx, sx + length, yy, 0.7, rng),
      );
    }
  }

  // The splatter flicked off the end: a cone that opens from the finger tips to
  // the right edge of the box. It is spread over the strip the fingers leave
  // instead of being stacked in one column — a column of dots reads as a dotted
  // rule — and it is kept inside the box, because a droplet sliced by the edge
  // reads as a cut shape.
  final droplets = <PaintDroplet>[];
  final dropCount = (dropletCount ?? 16).clamp(0, 24).toInt();
  final splatterStart = bodyRight + fingerReach * 0.55;
  final splatterSpan = math.max(0.0, width - 2 - splatterStart);
  for (var i = 0; i < dropCount; i++) {
    final t = rng.nextDouble();
    final distance = splatterStart + splatterSpan * t;
    // Size follows the position along the cone, not the raw distance: the strip
    // is only about 30dp deep, so a distance-driven size would make every drop
    // the same. The near ones stay 2–4dp and the far ones 0.8dp.
    final radius = math.max(
      0.8,
      (3.6 - 2.8 * t) * (0.55 + 0.45 * rng.nextDouble()),
    );
    // The cone opens with the distance from the body: tight at the tips, and
    // narrower than the band even at the far end so the drops never line up
    // along its edges.
    final half = bandHeight * (0.10 + 0.28 * t);
    final center = Offset(distance, mid + (rng.nextDouble() - 0.5) * 2 * half);
    if (center.dx + radius > width - 1) continue;
    if (center.dy - radius < 0 || center.dy + radius > height) continue;
    droplets.add(PaintDroplet(center: center, radius: radius));
  }

  final tipRight = fingers.isEmpty
      ? bodyRight
      : fingers.map((finger) => finger.$3).reduce((a, b) => math.max(a, b));

  return PaintSwipe(
    body: body,
    droplets: droplets,
    band: band,
    bodyRight: bodyRight,
    tipRight: tipRight,
    splatterAt: ((bodyRight + 2) / (width + 4)).clamp(0.0, 1.0).toDouble(),
  );
}

/// A little seeded roughness on a band edge.
///
/// The sine alone is too smooth to read as paint at arm's length; a small
/// jitter on every sample is what breaks the edge up without turning it into
/// noise.
double _jitterAt(math.Random rng, double amount) =>
    (rng.nextDouble() - 0.5) * 2 * amount;

/// A closed Catmull-Rom spline through [points], as cubic Béziers.
///
/// The curve passes through every sample (unlike [smoothClosedPath], which only
/// touches the midpoints), which is what keeps a finger's tip exactly where the
/// layout put it. The tension is the mock-up's 1/6.
Path _catmullRomPath(List<Offset> points) {
  final path = Path();
  final n = points.length;
  if (n < 3) return path;
  path.moveTo(points[0].dx, points[0].dy);
  for (var i = 0; i < n; i++) {
    final previous = points[(i - 1 + n) % n];
    final current = points[i];
    final next = points[(i + 1) % n];
    final after = points[(i + 2) % n];
    final c1 = current + (next - previous) / 6;
    final c2 = next - (after - current) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, next.dx, next.dy);
  }
  path.close();
  return path;
}

/// A thin lens with tapered ends: one dry streak.
///
/// A streak that stopped square would read as a slit cut with a knife; a brush
/// running out of paint leaves a mark that fades at both ends.
Path _streakPath(double x0, double x1, double y, double half, math.Random rng) {
  const steps = 6;
  final phase = rng.nextDouble() * math.pi * 2;
  final top = <Offset>[];
  final bottom = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final taper = math.pow(math.sin(math.pi * t), 0.6).toDouble();
    final wobble = math.sin(2 * math.pi * 1.6 * t + phase) * 0.6;
    final x = x0 + (x1 - x0) * t;
    top.add(Offset(x, y + wobble - half * taper));
    bottom.add(Offset(x, y + wobble + half * taper));
  }
  return smoothClosedPath([...top, ...bottom.reversed]);
}
