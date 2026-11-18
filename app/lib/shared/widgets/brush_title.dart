import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'paint/paint.dart';

/// A screen title with the hand-painted underline the tab headers carry.
///
/// The friends and profile tabs build the same pair by hand inside their
/// scrolling content, where the height is free. A pushed screen has to live in an
/// [AppBar] instead, whose toolbar height is fixed and whose title is clipped to
/// it, so this one also reports the height the toolbar needs at the current text
/// scale: the title alone already fills the default 56dp at 200%, and a fixed
/// toolbar would cut the stroke off.
class BrushTitle extends StatelessWidget {
  const BrushTitle({
    super.key,
    required this.title,
    required this.seed,
    this.strokeWidth = 84,
  });

  final String title;

  /// Seeded so the stroke keeps its exact raggedness across rebuilds.
  final int seed;

  /// Width of the stroke. A short title gets a short underline, the same
  /// proportion the tab headers use.
  final double strokeWidth;

  /// Thickness of the stroke. The stroke sits directly under the title, the same
  /// way the tab headers draw it.
  static const double _strokeHeight = 9;

  /// The toolbar height this title needs at the current text scale.
  ///
  /// The title and the stroke are stacked, so the toolbar has to fit both plus a
  /// little air; [kToolbarHeight] stays the floor so a screen does not shrink its
  /// toolbar at the default scale.
  static double toolbarHeight(BuildContext context) {
    final style = AppTextStyles.sectionTitle;
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        (style.height ?? 1.2);
    return math.max(
      kToolbarHeight,
      line + _strokeHeight + AppSpacing.s8,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: AppTextStyles.sectionTitle),
      BrushStroke(
        seed: seed,
        size: Size(strokeWidth, _strokeHeight),
        color: AppColors.purple.withValues(alpha: 0.55),
      ),
    ],
  );
}
