import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale from docs/design/Design.md 3.2.
///
/// Headings use the bundled rounded font; body text stays on the platform
/// default so long Japanese sentences keep their familiar rhythm.
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
    fontSize: 15,
    fontWeight: FontWeight.w600,
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
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.muted,
  );
}
