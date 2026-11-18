import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale from docs/design/Design.md 3.2.
///
/// Every style, body text included, uses the bundled M PLUS Rounded 1c.
///
/// Body text used to stay on the platform font. On Android, Flutter does not
/// pick the system font the way native apps do: when a font lacks a kanji,
/// Skia searches the system fallbacks, and on some phones (seen on a Redmi
/// Note 11 Pro 5G / MIUI) it lands on the Mincho face that fonts.xml only
/// registers as the fallback for `serif`. Kana stayed gothic and kanji turned
/// Mincho inside one line, and a Japanese locale did not change it. The
/// bundled font covers the kanji the app uses, so nothing falls back.
///
/// Body and caption are w500 because only 500 / 700 / 800 are bundled: the
/// design's 600 would resolve to the 700 file and sit too close to the
/// 800 headings.
abstract final class AppTextStyles {
  static const fontFamily = 'MPlusRounded';

  static const logo = TextStyle(
    fontFamily: fontFamily,
    fontSize: 44,
    fontWeight: FontWeight.w800,
    height: 1,
    letterSpacing: -1.5,
    color: AppColors.ink,
  );

  static const heroTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static const sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 23,
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: AppColors.ink,
  );

  static const friendName = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.ink,
  );

  static const button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 19,
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: AppColors.ink,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.muted,
  );
}
