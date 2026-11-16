import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// 「さそう」 pill. The visible pill is 36dp tall but the tap target is 48dp.
class KnockPill extends StatelessWidget {
  const KnockPill({super.key, required this.friendName, required this.onTap});

  final String friendName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$friendNameさんをさそう',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: SizedBox(
        height: AppSpacing.minTapTarget,
        child: Center(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(
                color: AppColors.purple,
                width: AppSpacing.borderWidth,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.send_rounded,
                  size: 14,
                  color: AppColors.purple,
                ),
                const SizedBox(width: AppSpacing.s4),
                Text(
                  'さそう',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
