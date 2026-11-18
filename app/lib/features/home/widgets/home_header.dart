import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/hima_logo.dart';

/// Home header: the `hima.` wordmark plus the bells that open knocks and
/// settings. Both icon buttons keep a 48dp tap target.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.hasKnockBadge,
    required this.onOpenKnocks,
    required this.onOpenSettings,
  });

  final bool hasKnockBadge;
  final VoidCallback onOpenKnocks;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // The wordmark is a brand mark rather than body text, so it keeps its
      // size; otherwise a large text scale would push the two 48dp buttons off
      // a 360dp screen.
      MediaQuery.withNoTextScaling(child: const HimaLogo(fontSize: 38)),
      const Spacer(),
      _HeaderIconButton(
        icon: Icons.notifications_none_rounded,
        label: 'ノック',
        showBadge: hasKnockBadge,
        onTap: onOpenKnocks,
      ),
      const SizedBox(width: AppSpacing.s4),
      _HeaderIconButton(
        icon: Icons.settings_outlined,
        label: '設定',
        onTap: onOpenSettings,
      ),
    ],
  );
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showBadge = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: showBadge ? '$label、新着あり' : label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.purpleSoft.withValues(alpha: 0.6),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 24, color: AppColors.ink),
                Positioned(
                  top: 10,
                  right: 11,
                  child: AnimatedScale(
                    scale: showBadge ? 1 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
