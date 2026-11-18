import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';

/// 30分 / 1時間 / 2時間 picker used by the tappable remaining-time pill.
Future<int?> showDurationPicker(
  BuildContext context, {
  required int current,
}) => showModalBottomSheet<int>(
  context: context,
  useSafeArea: true,
  builder: (sheetContext) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s24,
      0,
      AppSpacing.s24,
      AppSpacing.s24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ひまの長さ', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.s12),
        for (final minutes in himaDurationChoices)
          _ChoiceTile(
            label: durationLabel(minutes),
            selected: minutes == current,
            onTap: () => Navigator.of(sheetContext).pop(minutes),
          ),
      ],
    ),
  ),
);

/// Small mood picker opened from the hero badge while declared.
Future<Mood?> showMoodPicker(BuildContext context, {required Mood current}) =>
    showModalBottomSheet<Mood>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s24,
          0,
          AppSpacing.s24,
          AppSpacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('温度感', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.s12),
            for (final mood in Mood.values)
              _ChoiceTile(
                label: '${mood.emoji} ${mood.label}',
                selected: mood == current,
                onTap: () => Navigator.of(sheetContext).pop(mood),
              ),
          ],
        ),
      ),
    );

/// The activity picked in [showActivityPicker].
///
/// A plain `Activity?` cannot express the difference between "dismissed" and
/// "cleared", and clearing the choice has to reach the API.
class ActivityChoice {
  const ActivityChoice(this.activity);

  final Activity? activity;
}

/// 「なにする？」 picker opened from the declared hero's meta row.
///
/// The declared hero hides the chip row to stay calm, so the same single
/// optional choice is offered here instead. Dismissing the sheet returns null;
/// choosing 「なし」 returns a choice with a null activity.
Future<ActivityChoice?> showActivityPicker(
  BuildContext context, {
  required Activity? current,
}) => showModalBottomSheet<ActivityChoice>(
  context: context,
  useSafeArea: true,
  builder: (sheetContext) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s24,
      0,
      AppSpacing.s24,
      AppSpacing.s24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('なにする？', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.s12),
        for (final activity in Activity.values)
          _ChoiceTile(
            label: activity.label,
            selected: activity == current,
            leading: _ActivityLeading(activity: activity),
            onTap: () {
              AppHaptics.select();
              Navigator.of(sheetContext).pop(ActivityChoice(activity));
            },
          ),
        _ChoiceTile(
          label: 'なし',
          selected: current == null,
          onTap: () {
            AppHaptics.select();
            Navigator.of(sheetContext).pop(const ActivityChoice(null));
          },
        ),
      ],
    ),
  ),
);

class _ActivityLeading extends StatelessWidget {
  const _ActivityLeading({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final style = ActivityStyle.of(activity);
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(right: AppSpacing.s12),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
      child: Icon(style.icon, size: 18, color: style.accent),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    // `excludeSemantics` drops the InkWell below, including its tap action, so
    // the node has to carry the action itself or the choice is unreachable for
    // screen reader users.
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.s8),
        decoration: BoxDecoration(
          color: selected ? AppColors.purpleSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? AppColors.purple : AppColors.purpleSoft,
            width: AppSpacing.borderWidth,
          ),
        ),
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                style: AppTextStyles.body.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.purple,
              ),
          ],
        ),
      ),
    ),
  );
}
