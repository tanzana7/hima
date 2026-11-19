import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/paint/paint.dart';

/// The room the hero's blob keeps between its paint and its content.
///
/// Both states lay their content out with this, and the declare surface inside
/// the same value, so the declared paint covers the idle one exactly and the
/// wipe reveals a shape that lines up with it.
const EdgeInsets heroBlobPadding = EdgeInsets.fromLTRB(18, 20, 18, 20);

/// The hero's one blob silhouette.
///
/// The idle and the declared states are the same lump of paint in two colours:
/// the declared paint then covers the idle paint to the edge, nothing shows
/// around it, and the wipe can take the pink off to reveal the paper state
/// underneath without a silhouette jump.
const int heroBlobSeed = 20261117;

const double _heroBlobWobble = 0.075;
const int _heroBlobDroplets = 14;
const int _heroBlobArms = 4;
const double _heroBlobArmLength = 0.05;

/// The hero's paint: a thick blob, in the idle or in the declared colours.
class HeroPaint extends StatelessWidget {
  const HeroPaint({
    super.key,
    required this.colors,
    this.child,
    this.progress = 1,
    this.wipe = 0,
  });

  /// `[top, bottom]` from [AppColors].
  final List<Color> colors;

  final Widget? child;

  /// The declaration's landing. The body never shrinks below its resting size,
  /// so the heading always has paint under it.
  final double progress;

  /// 0 → the whole blob, 1 → wiped off. Only a user's 「おわる」 moves it.
  final double wipe;

  @override
  Widget build(BuildContext context) => PaintThick(
    seed: heroBlobSeed,
    colors: colors,
    padding: heroBlobPadding,
    wobble: _heroBlobWobble,
    droplets: _heroBlobDroplets,
    arms: _heroBlobArms,
    armLength: _heroBlobArmLength,
    progress: progress,
    wipe: wipe,
    // Repeated bristle and wipe maps read as wood grain and expose their tile
    // edges. The hero uses its gradient, gloss, and ragged wipe silhouette.
    bristles: false,
    dryEdge: false,
    child: child,
  );
}

/// The paper state of the hero's blob.
const List<Color> heroIdleColors = [
  AppColors.heroIdleTop,
  AppColors.heroIdleBottom,
];

/// The declared state of the hero's blob.
const List<Color> heroDeclaredColors = [
  AppColors.heroDeclaredTop,
  AppColors.heroDeclaredBottom,
];

/// The idle blob, for the paint the declared state is wiped off to reveal.
///
/// It is the same widget [DeclareButton] paints, so the reveal is the paper
/// state and not a second, subtly different blob.
class HeroIdlePaint extends StatelessWidget {
  const HeroIdlePaint({super.key, this.child, this.progress = 1});

  final Widget? child;
  final double progress;

  @override
  Widget build(BuildContext context) =>
      HeroPaint(colors: heroIdleColors, progress: progress, child: child);
}
