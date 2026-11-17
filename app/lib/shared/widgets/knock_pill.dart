import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// 「さそう」 pill, plus the states a knock can put it in.
///
/// The pill has no fixed height: at 200% text scale the old 36dp box clipped the
/// label vertically. It keeps a minimum size and grows with the text instead.
class KnockPill extends StatelessWidget {
  const KnockPill({
    super.key,
    required this.friendName,
    required this.onTap,
    this.sent = false,
    this.accepted = false,
    this.expand = false,
    this.dense = false,
  });

  final String friendName;
  final VoidCallback onTap;

  /// A knock to this person is still waiting for an answer. The pill turns into
  /// a muted 「さそった」 and stops accepting taps, so the same person cannot be
  /// invited twice from the match card or the friend grid.
  final bool sent;

  /// The knock was answered 「いいよ！」. Without this the pill dropped back to
  /// 「さそう」 as soon as the answer arrived, which hid the good news and made
  /// the friend look like they had never been asked.
  final bool accepted;

  /// Stretches the pill across its parent, used by the home friend cards.
  final bool expand;

  /// Smaller label for the match card, where several pills sit side by side.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final locked = sent || accepted;
    final foreground = accepted
        ? AppColors.success
        : (sent ? AppColors.muted : AppColors.purple);
    final label = accepted ? 'いいよ！' : (sent ? 'さそった' : 'さそう');
    final icon = accepted
        ? Icons.celebration_rounded
        : (sent ? Icons.check_rounded : Icons.send_rounded);
    return Semantics(
      button: !locked,
      enabled: !locked,
      label: accepted
          ? '$friendNameさんから いいよ！'
          : (sent ? '$friendNameさんにさそった' : '$friendNameさんをさそう'),
      excludeSemantics: true,
      child: InkWell(
        onTap: locked ? null : onTap,
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
                  color: accepted
                      ? AppColors.mintSoft
                      : (sent
                            ? AppColors.surface.withValues(alpha: 0.65)
                            : AppColors.surface),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(
                    color: accepted
                        ? AppColors.success
                        : (sent ? AppColors.purpleSoft : AppColors.purple),
                    width: AppSpacing.borderWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: dense ? 11 : 14, color: foreground),
                    const SizedBox(width: AppSpacing.s4),
                    Flexible(
                      child: Text(
                        label,
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
