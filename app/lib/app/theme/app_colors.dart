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
  static const danger = Color(0xFFD93F58);

  /// Friend card tints. Rotated per card; the color has no meaning.
  static const List<Color> friendTints = [
    purpleSoft,
    skySoft,
    peachSoft,
    mintSoft,
  ];
}
