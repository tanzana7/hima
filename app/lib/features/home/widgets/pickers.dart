import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';

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

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
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
