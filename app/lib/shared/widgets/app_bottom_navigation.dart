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
/// There is no bar. No strip, no wash, no wavy edge: the tabs sit directly on
/// the paper, and the only background is a vertical fade from transparent to
/// the paper colour over the top of the box. A shape spanning the width — even
/// a soft one with an irregular top edge — still reads as a bar, which is what
/// the previous lavender band did.
///
/// The shell floats this nav over the content (`Scaffold.extendBody`), so a
/// list scrolls underneath it instead of being cut off at its top edge. The
/// fade is what makes that seam disappear: the content dissolves into the paper
/// over [fadeHeight] and the solid area below it hides the rest.
///
/// The selected tab gets a small splash behind its icon, one colour per tab: a
/// body, one or two short arms and a few droplets, and no drip, because a drip
/// hanging off the splash would run into the label under it. It splashes in on
/// selection and shrinks away on deselection, and the tap plays the shared
/// selection haptic. Unselected icons and labels are ink at 68% on paper, which
/// is 5.7:1 — above the 4.5:1 that a 13sp label needs.
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

  /// Height of the transparent-to-paper fade painted above the tabs.
  ///
  /// It is a fixed height rather than a fraction of the nav: the nav grows with
  /// the text scale (a 200% label is taller than a 13sp one), and a fractional
  /// stop would make the fade band change height with it. 48–72dp is the range
  /// where scrolled content dissolves into the paper instead of ending at a
  /// straight edge, and it also leaves the selected tab's splash room to throw
  /// an arm upwards.
  static const double fadeHeight = 56;

  /// The bottom padding a scrolling tab keeps so its last item can be scrolled
  /// clear of the nav.
  ///
  /// The nav floats over the content, and `Scaffold.extendBody` makes the
  /// scaffold report the nav's height as the body's bottom `MediaQuery`
  /// padding. Reading it back instead of hard-coding a height is what keeps the
  /// last card reachable at 200% text scale, where the tabs are taller, and on
  /// a device with a taller system inset.
  static double listBottomInset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + AppSpacing.s32;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    // Stretch, not centre: both bands are full-width and neither has an
    // intrinsic width of its own.
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // A gradient, not a shape: it has no edge to see, so the nav never
      // becomes a band. It ends exactly on the paper colour, so it meets the
      // solid area below without a seam of its own.
      SizedBox(
        height: fadeHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withValues(alpha: 0),
                AppColors.background,
              ],
            ),
          ),
        ),
      ),
      // Solid paper behind the tabs and the system inset. Nothing scrolls
      // through this part: by the time content reaches it, the fade has already
      // taken it to the paper colour.
      ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s8,
              0,
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
      ),
    ],
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
  /// Diameter of the splash behind the icon. The icon is centred on it and
  /// stays inside the blob's safe rect, so the paint never covers the glyph.
  static const _splatSize = 44.0;

  /// Unselected ink. 68% of [AppColors.ink] on the paper is 5.7:1, which keeps
  /// the 13sp labels above the 4.5:1 that small text needs; 60% would be 4.4:1
  /// and 50% would fail outright.
  static const _idleInk = 0.68;

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
    final color = widget.selected
        ? AppColors.ink
        : AppColors.ink.withValues(alpha: _idleInk);
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
                  // The arms and droplets leave the icon box on purpose; the
                  // tab is two and a half times wider than the splash, so there
                  // is room for them without touching the next tab.
                  child: Stack(
                    clipBehavior: Clip.none,
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
                              // selection, on top of the splash's own
                              // overshoot.
                              scale: 0.72 + 0.28 * value,
                              // Rebuilt with the controller so the arms shoot
                              // out and the droplets fly as it arrives; the seed
                              // keeps the silhouette identical every time.
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
                                wobble: 0.085,
                                // A mini splash: a body, one or two short arms
                                // and a couple of droplets. No drip — it would
                                // hang over the label — and the arms are kept
                                // short enough that a downward one still stops
                                // in the gap above the label.
                                arms: 2,
                                armLength: 0.12,
                                droplets: 3,
                                drips: 0,
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
                // 10dp: room for the splash's arms and wobble to stop short of
                // the label, so the paint never runs into the text.
                const SizedBox(height: 10),
                // One line, scaled down to the tab: the label is a single
                // phrase, and Japanese offers a break between any two
                // characters, so letting it wrap split 「プロフィール」 as
                // 「プロフィ／ール」. An ellipsis would hide part of the name
                // instead. The Semantics node above carries the plain label.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.destination.label,
                    maxLines: 1,
                    softWrap: false,
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
