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

  /// Hero backdrops. The declared hero is a bright coral→pink splash; the idle
  /// one a quiet lavender→lemon wash, so the two states read differently
  /// without the idle state looking like a warning.
  ///
  /// **Contrast.** The only text directly on the declared paint is the heading:
  /// 34sp, weight 800, i.e. WCAG *large* text, whose threshold is **3:1** rather
  /// than 4.5:1. Every small label in the hero sits on a white paint dab. So the
  /// stops only have to clear 3:1, and they do: white on [heroDeclaredTop] is
  /// 3.8:1 and on [heroDeclaredBottom] 3.4:1. An earlier version darkened the
  /// paint to `#C2143F` to reach 4.5:1 for text that does not need it, which
  /// turned the brand's happy coral into a dark crimson.
  static const heroDeclaredTop = Color(0xFFEE3F6A);
  static const heroDeclaredBottom = Color(0xFFF0507A);
  static const heroIdleTop = Color(0xFFF1E6FF);
  static const heroIdleBottom = Color(0xFFFFF3C4);

  /// Friend card tints. Rotated per card; the color has no meaning.
  static const List<Color> friendTints = [
    purpleSoft,
    skySoft,
    peachSoft,
    mintSoft,
  ];
}
