import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import 'app_colors.dart';

/// How one activity looks wherever it is shown.
///
/// The chips, the declared hero's meta row and the friend cards all read from
/// here, so 「ゲーム」 keeps its colour and icon across the screen instead of
/// every widget inventing its own. The tint carries no meaning on its own: the
/// label always says the activity too.
class ActivityStyle {
  const ActivityStyle({
    required this.background,
    required this.accent,
    required this.icon,
  });

  final Color background;

  /// Colour of the small icon. Text stays [AppColors.ink] for contrast.
  final Color accent;

  final IconData icon;

  static ActivityStyle of(Activity activity) => switch (activity) {
    Activity.game => const ActivityStyle(
      background: AppColors.purpleSoft,
      accent: AppColors.purple,
      icon: Icons.sports_esports_rounded,
    ),
    Activity.chat => const ActivityStyle(
      background: AppColors.mintSoft,
      accent: AppColors.teal,
      icon: Icons.call_rounded,
    ),
    Activity.work => const ActivityStyle(
      background: AppColors.skySoft,
      accent: AppColors.blue,
      icon: Icons.laptop_mac_rounded,
    ),
    Activity.out => const ActivityStyle(
      background: AppColors.peachSoft,
      accent: AppColors.orange,
      icon: Icons.directions_walk_rounded,
    ),
    Activity.any => const ActivityStyle(
      background: AppColors.lemonSoft,
      accent: AppColors.ink,
      icon: Icons.star_rounded,
    ),
  };
}
