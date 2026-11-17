import 'package:flutter/material.dart';

import 'paint_geometry.dart';
import 'paint_splat.dart';

/// The background of a button, pill or chip: a squashed, slightly lopsided
/// blob instead of an outlined stadium.
///
/// It is [PaintSplat] with the defaults a control needs — no drips, a small
/// wobble, a tonal gradient — so there is one blob implementation and two
/// vocabularies. [padding] is the room the label keeps from the edge; the paint
/// fills it and spills a little past it.
class PaintDab extends StatelessWidget {
  const PaintDab({
    super.key,
    required this.seed,
    required this.color,
    this.child,
    this.size = Size.zero,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    this.wobble = 0.04,
    this.droplets = 0,
    this.highlight,
  });

  final int seed;
  final Color color;
  final Widget? child;
  final Size size;
  final EdgeInsets padding;
  final double wobble;

  /// Small droplets beside the dab. One or two turn the selected chip into a
  /// splash without making the row noisy.
  final int droplets;

  /// The lighter end of the fill. Defaults to a lifted tone of [color].
  final Color? highlight;

  @override
  Widget build(BuildContext context) => PaintSplat(
    seed: seed,
    colors: [highlight ?? paintTone(color, 0.18), color],
    size: size,
    padding: padding,
    corner: 999,
    wobble: wobble,
    droplets: droplets,
    drips: 0,
    child: child,
  );
}
