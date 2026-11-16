import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/knock_pill.dart';
import '../hero_state.dart';

/// One friend in the home grid: a large avatar on the left, name, mood +
/// activity and the remaining time on the right, さそう across the bottom.
///
/// The old layout stacked a small avatar, a wrapped name, the status and a
/// centred pill, which left a lot of empty space and never showed how long the
/// friend stays free. The card tint rotates per card and carries no meaning; the
/// state is always written out in text as well.
class FriendStatusCard extends StatelessWidget {
  const FriendStatusCard({
    super.key,
    required this.friend,
    required this.tint,
    required this.pending,
    required this.onKnock,
  });

  final HimaSession friend;
  final Color tint;

  /// My knock to this friend is still waiting for an answer.
  final bool pending;

  final VoidCallback onKnock;

  @override
  Widget build(BuildContext context) {
    final activity = friend.activity;
    final status = activity == null
        ? '${friend.mood.emoji} ひま'
        : '${friend.mood.emoji} ${activity.label}';
    return Container(
      // The pill brings its own tap-target padding, so the card only needs a
      // little room underneath it.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarView(
                name: friend.user.displayName,
                imageUrl: friend.user.avatarUrl,
                size: 56,
                background: AppColors.surface.withValues(alpha: 0.85),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      friend.user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.friendName.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      himaRemainingLabel(friend.expiresAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          KnockPill(
            friendName: friend.user.displayName,
            onTap: onKnock,
            sent: pending,
            expand: true,
          ),
        ],
      ),
    );
  }
}
