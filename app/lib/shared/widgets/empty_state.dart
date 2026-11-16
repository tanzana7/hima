import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

/// Quiet placeholder for empty and error states of a list.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.hourglass_empty_rounded,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s16,
      vertical: AppSpacing.s24,
    ),
    child: Column(
      children: [
        Icon(icon, size: 30, color: AppColors.muted),
        const SizedBox(height: AppSpacing.s8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: AppColors.muted),
        ),
        if (action case final action?) ...[
          const SizedBox(height: AppSpacing.s12),
          action,
        ],
      ],
    ),
  );
}

/// Loading placeholder that keeps the layout height stable.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message = '読み込み中…'});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          message,
          style: AppTextStyles.caption.copyWith(color: AppColors.muted),
        ),
      ],
    ),
  );
}
