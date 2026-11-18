import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../data/models/models.dart';

/// The mood emoji that sits on the corner of an avatar.
///
/// It lives here because the hero, the match cards and the friend cards all show
/// the same badge and all three have to keep the emoji inside its circle.
///
/// The circle keeps a fixed diameter and the emoji is drawn at its design size
/// whatever the text scale is: growing the glyph made it spill out of the white
/// disc and read as a cut-off emoji, and growing the disc would push the badge
/// off the avatar it belongs to. Nothing is lost at large text scales because
/// [Mood.label] is what a screen reader announces.
class MoodBadge extends StatelessWidget {
  const MoodBadge({
    super.key,
    required this.mood,
    this.size = 22,
    this.emojiSize = 11,
    this.elevated = true,
  });

  final Mood mood;

  /// Diameter of the white disc.
  final double size;

  /// Emoji size at 100% text scale; the text scale never enlarges it.
  final double emojiSize;

  /// Draws the soft shadow the badge needs to stay legible on a photo.
  final bool elevated;

  @override
  Widget build(BuildContext context) => Semantics(
    label: mood.label,
    child: ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: elevated
              ? [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1,
          child: Text(
            mood.emoji,
            maxLines: 1,
            // `height: 1` keeps the line box on the glyph, so the emoji is
            // centred in the disc instead of sitting on a taller baseline.
            style: TextStyle(fontSize: emojiSize, height: 1),
          ),
        ),
      ),
    ),
  );
}
