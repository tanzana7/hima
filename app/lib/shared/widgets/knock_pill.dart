import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// 「さそう」 pill, plus the 「さそった」 state shown while my knock is pending.
///
/// The pill has no fixed height: at 200% text scale the old 36dp box clipped the
/// label vertically. It keeps a minimum size and grows with the text instead.
class KnockPill extends StatelessWidget {
  const KnockPill({
    super.key,
    required this.friendName,
    required this.onTap,
    this.sent = false,
    this.expand = false,
    this.dense = false,
  });

  final String friendName;
  final VoidCallback onTap;

  /// A knock to this person is still waiting for an answer. The pill turns into
  /// a muted 「さそった」 and stops accepting taps, so the same person cannot be
  /// invited twice from the match card or the friend grid.
  final bool sent;

  /// Stretches the pill across its parent, used by the home friend cards.
  final bool expand;

  /// Smaller label for the match card, where several pills sit side by side.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final foreground = sent ? AppColors.muted : AppColors.purple;
    return Semantics(
      button: !sent,
      enabled: !sent,
      label: sent ? '$friendNameさんにさそった' : '$friendNameさんをさそう',
      excludeSemantics: true,
      child: InkWell(
        onTap: sent ? null : onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: ConstrainedBox(
          // The tap target stays 48dp while the visible pill is allowed to grow
          // past it.
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: dense ? 32 : 40),
              child: Container(
                width: expand ? double.infinity : null,
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 6 : AppSpacing.s12,
                  vertical: dense ? AppSpacing.s4 : AppSpacing.s8,
                ),
                decoration: BoxDecoration(
                  color: sent
                      ? AppColors.surface.withValues(alpha: 0.65)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(
                    color: sent ? AppColors.purpleSoft : AppColors.purple,
                    width: AppSpacing.borderWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      sent ? Icons.check_rounded : Icons.send_rounded,
                      size: dense ? 11 : 14,
                      color: foreground,
                    ),
                    const SizedBox(width: AppSpacing.s4),
                    Flexible(
                      child: Text(
                        sent ? 'さそった' : 'さそう',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 10 : 13,
                          fontWeight: FontWeight.w800,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
