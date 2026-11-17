import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../haptics.dart';
import 'paint/paint.dart';

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

/// Bottom navigation painted as a splash of colour on paper.
///
/// There is no strip: a [PaintSwash] spans the width and runs off the bottom of
/// the box, so its irregular top edge is the only boundary between the page and
/// the bar — no straight seam, no hairline, no pill indicator.
///
/// The selected tab gets a paint splat behind its icon, one colour per tab. It
/// splashes in on selection and shrinks away on deselection, and the tap plays
/// the shared selection haptic. Unselected icons are plain on the paper.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// One colour per tab, all light enough for the ink icon on top (the lowest
  /// pair is 7.2:1).
  static const _tabTints = [
    AppColors.coralLight,
    AppColors.mint,
    AppColors.yellow,
  ];

  /// Room above the icons for the swash's wobbling edge.
  static const _washHeadroom = 20.0;

  @override
  Widget build(BuildContext context) => PaintSwash(
    seed: 8123,
    color: AppColors.purple,
    top: _washHeadroom - 6,
    wobble: 5,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s8,
          _washHeadroom,
          AppSpacing.s8,
          AppSpacing.s8,
        ),
        child: Row(
          children: [
            for (var index = 0; index < appNavDestinations.length; index++)
              Expanded(
                child: _NavItem(
                  destination: appNavDestinations[index],
                  tint: _tabTints[index % _tabTints.length],
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

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  /// Diameter of the splat behind the icon. The icon is centred on it and stays
  /// inside the blob's safe rect, so the paint never covers the glyph.
  static const _splatSize = 44.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: widget.selected ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion keeps the end states and drops the splash entirely.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.selected ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(_NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.selected ? 1 : 0;
      return;
    }
    if (widget.selected) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? AppColors.ink : AppColors.muted;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.destination.label,
      // `excludeSemantics` replaces the child's semantics, action included, so
      // the node has to carry the tap itself or a screen reader announces the
      // tab as a button it cannot activate.
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _splatSize,
                  height: _splatSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final value = _controller.value.clamp(0.0, 1.0);
                          if (value <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Opacity(
                            opacity: value,
                            child: Transform.scale(
                              // Shrinks away on deselection and grows in on
                              // selection, on top of the splat's own overshoot.
                              scale: 0.72 + 0.28 * value,
                              // Rebuilt with the controller so the droplets fly
                              // out and the blob overshoots as it arrives; the
                              // seed keeps the silhouette identical every time.
                              child: PaintSplat(
                                seed: paintSeedOf(
                                  'nav-${widget.destination.label}',
                                ),
                                colors: [
                                  paintTone(widget.tint, 0.22),
                                  widget.tint,
                                ],
                                size: const Size.square(_splatSize),
                                padding: const EdgeInsets.all(9),
                                wobble: 0.07,
                                droplets: 3,
                                progress: value,
                              ),
                            ),
                          );
                        },
                      ),
                      Icon(
                        widget.selected
                            ? widget.destination.selectedIcon
                            : widget.destination.icon,
                        color: color,
                        size: 23,
                      ),
                    ],
                  ),
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
                    widget.destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: color,
                      fontWeight: widget.selected
                          ? FontWeight.w800
                          : FontWeight.w600,
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
