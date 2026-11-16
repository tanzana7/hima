import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/knock_pill.dart';

/// One friend in the home grid: avatar, name, mood + activity, さそう.
///
/// The card tint rotates per card and carries no meaning; the state is always
/// written out in text as well.
class FriendStatusCard extends StatelessWidget {
  const FriendStatusCard({
    super.key,
    required this.friend,
    required this.tint,
    required this.onKnock,
  });

  final HimaSession friend;
  final Color tint;
  final VoidCallback onKnock;

  @override
  Widget build(BuildContext context) {
    final activity = friend.activity;
    final status = activity == null
        ? '${friend.mood.emoji} ひま'
        : '${friend.mood.emoji} ${activity.label}';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarView(
                name: friend.user.displayName,
                imageUrl: friend.user.avatarUrl,
                size: 40,
                background: AppColors.surface.withValues(alpha: 0.85),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    friend.user.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.friendName,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.s4),
          Align(
            alignment: Alignment.centerRight,
            child: KnockPill(friendName: friend.user.displayName, onTap: onKnock),
          ),
        ],
      ),
    );
  }
}
