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
/// They sit on the paper directly under the hero's stroke. The usual-width row
/// scrolls horizontally; narrow rows and large text scales wrap so labels do not
/// end mid-word.
/// Choosing an activity used to require scrolling past the whole friend grid,
/// so the choice was effectively hidden. Each activity keeps its own pastel
/// ([ActivityStyle]) so the row reads as playful dabs instead of five identical
/// chips.
///
/// **On paper, not on the band.** Inside the stroke the row was cut by the
/// band's straight right edge, and a fade over that edge took the chip labels'
/// contrast with it. Below the stroke the row is cut at the viewport edge like
/// any scroller; below 300dp or above 1.3 text scale the chips wrap so no label
/// is cut at that edge.
///
/// The selected chip is the same hue pushed toward the activity's accent and
/// carries a droplet or two, so the choice is shown by more paint rather than by
/// an outline.
class ActivityChips extends StatelessWidget {
  const ActivityChips({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onOpenPicker,
  });

  final Activity? selected;
  final ValueChanged<Activity?> onSelected;
  final ValueChanged<Offset> onOpenPicker;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget chip(Activity activity) => _ActivityChip(
        activity: activity,
        selected: selected == activity,
        onTap: () {
          AppHaptics.select();
          onSelected(selected == activity ? null : activity);
        },
      );

      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      // Keep every activity label readable on narrow phones and at large text
      // scales. At the usual width and scale the row stays compact and scrolls.
      if (constraints.maxWidth < 300 || textScale > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _activityLabel(context),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final activity in Activity.values) chip(activity),
              ],
            ),
          ],
        );
      }

      return Row(
        children: [
          _activityLabel(context),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final activity in Activity.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.s8),
                      child: chip(activity),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _activityLabel(BuildContext context) {
    Offset? origin;
    void open() => onOpenPicker(origin ?? Offset.zero);
    return Semantics(
      button: true,
      label: 'なにする？',
      hint: '活動を選ぶ',
      onTap: open,
      excludeSemantics: true,
      child: InkWell(
        onTapDown: (details) => origin = details.globalPosition,
        onTap: open,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded, size: 18, color: AppColors.coral),
              const SizedBox(width: AppSpacing.s4),
              Text(
                'なにする？',
                maxLines: 1,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      onTap: widget.onTap,
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
              wobble: 0.09,
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
