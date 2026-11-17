import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/paint/paint.dart';

/// 「なにする？」 chips. Optional, single select, and deselectable.
///
/// They sit inside the hero, directly under the main button, as one horizontally
/// scrolling row: choosing an activity used to require scrolling past the whole
/// friend grid, so the choice was effectively hidden. Each activity keeps its own
/// pastel ([ActivityStyle]) so the row reads as a set of playful dabs instead of
/// five identical chips.
///
/// The selected chip is the same hue pushed toward the activity's accent and
/// carries a droplet or two, so the choice is shown by more paint rather than by
/// an outline.
class ActivityChips extends StatelessWidget {
  const ActivityChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Activity? selected;
  final ValueChanged<Activity?> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // Kept as a compact inline label so the chips still read as the optional
      // 「なにする？」 choice (Design.md 4.4) without adding a second row.
      const Icon(Icons.bolt_rounded, size: 15, color: AppColors.coral),
      const SizedBox(width: 2),
      Text(
        'なにする？',
        maxLines: 1,
        style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(width: AppSpacing.s8),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final activity in Activity.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s8),
                  child: _ActivityChip(
                    activity: activity,
                    selected: selected == activity,
                    onTap: () {
                      AppHaptics.select();
                      onSelected(selected == activity ? null : activity);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ActivityChip extends StatefulWidget {
  const _ActivityChip({
    required this.activity,
    required this.selected,
    required this.onTap,
  });

  final Activity activity;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ActivityChip> createState() => _ActivityChipState();
}

class _ActivityChipState extends State<_ActivityChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final style = ActivityStyle.of(widget.activity);
    final fill = widget.selected
        ? Color.lerp(style.background, style.accent, 0.24)!
        : style.background;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.activity.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: fill),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (context, value, _) => PaintDab(
              seed: paintSeedOf('chip-${widget.activity.name}'),
              color: value ?? fill,
              // 14dp of vertical padding brings the dab to the 48dp tap target
              // without a fixed height, so it still grows with the text.
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              wobble: 0.045,
              droplets: widget.selected ? 2 : 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(style.icon, size: 16, color: style.accent),
                  const SizedBox(width: AppSpacing.s4 + 2),
                  Text(
                    widget.activity.label,
                    maxLines: 1,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 14,
                      fontWeight: widget.selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (widget.selected) ...[
                    const SizedBox(width: AppSpacing.s4),
                    const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: AppColors.ink,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
