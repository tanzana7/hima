/// The paint kit: small, composable `CustomPainter` primitives that give the
/// app a wet-paint look instead of a vector one.
///
/// Rules that hold for every primitive here:
///
/// * **Seeded.** Each shape takes an `int seed` (see [paintSeedOf]) and derives
///   its outline from it, so a card keeps the same silhouette across rebuilds,
///   polls and scrolling. Nothing draws from an unseeded `Random`.
/// * **Cached.** Paths are built once per (seed, size, config) and reused, so a
///   scrolling list does not re-sample an outline per frame.
/// * **Filled, never stroked.** A splash is a body plus arms plus droplets, all
///   of them filled shapes. No outline, no neck from the body to a droplet and
///   no drip drawn as a line: each of those reads as a pin or a lollipop.
/// * **Safe rect.** A primitive with a `child` lays it out inside the inner
///   rect left by `padding`; the paint is drawn in the full box and spills into
///   that band, so the decorative edge can never cover a label or a tap target.
/// * **Overflow is expected.** The wobble, the arms and the droplets leave the
///   widget box on purpose; the caller gives them room (`Clip.none`, a gap in
///   the layout, a bleed off the screen edge). Shrinking the paint until it
///   fits puts the straight edges back.
/// * **Wide strokes stay inside the box width.** [BrushSwipe] is the exception
///   to the bleed rule: a stroke cut off by the screen edge reads as a
///   rectangle again, so its frayed end and its splatter are paid for out of
///   the space the caller reserves for them instead of out of the edge.
/// * **Reduced motion.** The animated primitives take a `progress` and paint
///   the final state when `MediaQuery.disableAnimationsOf` is true.
library;

export 'brush_stroke.dart';
export 'brush_swipe.dart';
export 'paint_dab.dart';
export 'paint_geometry.dart';
export 'paint_mark.dart';
export 'paint_splat.dart';
export 'paint_swash.dart';
export 'paint_wash.dart';
export 'splatter_dots.dart';
