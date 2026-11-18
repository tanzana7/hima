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
///
/// [wobble] is a fraction of the short side, so a 40dp-tall chip needs a larger
/// number than a card to show the same edge movement: 0.08–0.10 is the range
/// where a pill stops looking ruled.
class PaintDab extends StatelessWidget {
  const PaintDab({
    super.key,
    required this.seed,
    required this.color,
    this.child,
    this.size = Size.zero,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    this.wobble = 0.08,
    this.droplets = 0,
    this.highlight,
    this.arms = 0,
    this.armLength = 0.10,
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

  /// Lobes where the paint spread. Off by default: a chip is a small control,
  /// and arms on it read as a torn edge rather than as a splash.
  final int arms;

  /// Arm length as a fraction of the short side. Only used when [arms] > 0.
  final double armLength;

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
    arms: arms,
    armLength: armLength,
    child: child,
  );
}
