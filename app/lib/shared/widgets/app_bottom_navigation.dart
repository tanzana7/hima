import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../haptics.dart';

class AppNavDestination {
  const AppNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const appNavDestinations = [
  AppNavDestination(
    label: 'ホーム',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  AppNavDestination(
    label: '友達',
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
  ),
  AppNavDestination(
    label: 'プロフィール',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

/// Bottom navigation with a purple pill for the active tab.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.purpleSoft, width: 1.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s8,
          AppSpacing.s8,
          AppSpacing.s8,
          AppSpacing.s8,
        ),
        child: Row(
          children: [
            for (var index = 0; index < appNavDestinations.length; index++)
              Expanded(
                child: _NavItem(
                  destination: appNavDestinations[index],
                  selected: index == selectedIndex,
                  onTap: () {
                    if (index == selectedIndex) return;
                    AppHaptics.select();
                    onSelected(index);
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = selected ? AppColors.purple : AppColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTapTarget,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
          decoration: BoxDecoration(
            color: selected ? AppColors.purpleSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 2),
              // The bar is a fixed strip at the bottom of the screen, so the
              // label is clamped to 130% instead of growing until
              // 「プロフィール」 turns into 「プロフィ…」. The labels are short and
              // the icon plus the semantics label still carry the meaning at
              // any system text size.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
