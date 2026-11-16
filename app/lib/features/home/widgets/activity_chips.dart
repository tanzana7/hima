import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/decorations.dart';

/// 「なにする？」 chips. Optional, single select, and deselectable.
class ActivityChips extends StatelessWidget {
  const ActivityChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Activity? selected;
  final ValueChanged<Activity?> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              'なにする？',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.sectionTitle,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          const StarAccent(size: 14),
        ],
      ),
      const SizedBox(height: AppSpacing.s12),
      SingleChildScrollView(
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
              horizontal: AppSpacing.s16,
              vertical: AppSpacing.s8,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppColors.purpleSoft
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(
                color: widget.selected
                    ? AppColors.purple
                    : AppColors.purpleSoft,
                width: AppSpacing.borderWidth,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.activity.emoji,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: AppSpacing.s4 + 2),
                Text(
                  widget.activity.label,
                  maxLines: 1,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 14,
                    fontWeight: widget.selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: widget.selected ? AppColors.ink : AppColors.muted,
                  ),
                ),
                if (widget.selected) ...[
                  const SizedBox(width: AppSpacing.s4),
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.purple,
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
