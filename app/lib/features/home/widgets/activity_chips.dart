import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';

/// 「なにする？」 chips. Optional, single select, and deselectable.
///
/// They sit inside the hero, directly under the main button, as one horizontally
/// scrolling row: choosing an activity used to require scrolling past the whole
/// friend grid, so the choice was effectively hidden. Each activity keeps its own
/// pastel tint and icon ([ActivityStyle]) so the row reads as a set of playful
/// stickers instead of five identical white chips.
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
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12 + 2,
              vertical: AppSpacing.s8,
            ),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(
                color: widget.selected ? AppColors.ink : Colors.transparent,
                width: AppSpacing.borderWidth,
              ),
            ),
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
    );
  }
}
