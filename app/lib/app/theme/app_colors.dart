import 'package:flutter/material.dart';

/// Color tokens from docs/design/Design.md 3.1.
///
/// The palette is white paper + deep purple ink with coral, yellow and lime
/// accents. Color never carries state on its own; text always says it too.
abstract final class AppColors {
  static const background = Color(0xFFFFFEFC);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2F124F);
  static const muted = Color(0xFF756B83);
  static const purple = Color(0xFF7538DC);
  static const purpleSoft = Color(0xFFF0E3FF);
  static const coral = Color(0xFFFF6389);
  static const coralLight = Color(0xFFFF8E86);
  static const yellow = Color(0xFFFFE65A);
  static const lime = Color(0xFFC5F35C);
  static const skySoft = Color(0xFFDDF6FF);
  static const mintSoft = Color(0xFFDDF9E9);
  static const peachSoft = Color(0xFFFFF0DC);
  static const lemonSoft = Color(0xFFFFF3BF);
  static const danger = Color(0xFFD93F58);

  /// Filled paint dabs for the knock button. White on [purple] is 6.3:1 and
  /// [ink] on [mint] / [mutedSoft] is above 12:1, so every state of 「さそう」
  /// clears 4.5:1 without lightening the text.
  static const mint = Color(0xFFA8EFC9);
  static const mutedSoft = Color(0xFFE7E3EC);

  /// 「いいよ！」: a knock the friend accepted.
  /// Shown as small text on [mintSoft], so it is kept dark enough for 4.5:1 contrast
  /// (about 5.3:1). Lightening it drops the pill text below WCAG AA.
  static const success = Color(0xFF13724A);

  /// Small icon accents for the activity tags. Only the icon takes the accent;
  /// the label stays [ink] so every tag keeps its contrast.
  static const teal = Color(0xFF0F7E70);
  static const blue = Color(0xFF1F6FB2);
  static const orange = Color(0xFFB4551A);

  /// Hero backdrops. The declared hero is a vivid hot-pink splash; the idle
  /// one a quiet lavender→lemon wash, so the two states read differently
  /// without the idle state looking like a warning.
  ///
  /// The hot-pink fill keeps the large white heading legible and makes the
  /// declared state read as a fresh splash of paint.
  static const heroDeclaredTop = Color(0xFFF83F98);
  static const heroDeclaredBottom = Color(0xFFE91E73);
  static const heroIdleTop = Color(0xFFF1E6FF);
  static const heroIdleBottom = Color(0xFFFFF3C4);

  /// Friend card tints. Rotated per card; the color has no meaning.
  static const List<Color> friendTints = [
    purpleSoft,
    skySoft,
    peachSoft,
    mintSoft,
  ];

  /// Saturated partners of [friendTints], in the same order.
  ///
  /// A heading's brush stroke takes its colour from here instead of darkening
  /// the wash underneath it: lerping a pastel towards black desaturates it, and
  /// the mint wash's underline came out grey-green and the peach one grey-brown.
  /// These are the palette's own clean tints, so the stroke stays the same hue
  /// as the group without turning muddy. It is decoration only (no text sits on
  /// it), so it does not have to clear a contrast ratio.
  static const List<Color> friendStrokeTints = [purple, sky, coral, mint];

  /// The saturated partner of [skySoft], used where a pale sky would read as
  /// grey. Kept out of the icon accents above: those are chosen for text and
  /// icon contrast on white.
  static const sky = Color(0xFF3FA9DC);
}
