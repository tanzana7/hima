import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/doodles.dart';
import '../../../shared/widgets/knock_pill.dart';
import '../hero_state.dart';

/// One friend in the home grid: a large ringed avatar, name and remaining time,
/// a pastel tag for what they want to do, and さそう across the bottom.
///
/// The card tint rotates per card and carries no meaning; the state is always
/// written out in text as well. The tag takes the activity's own colour and icon
/// ([ActivityStyle]) so the grid reads like a set of stickers instead of four
/// identical white cards.
class FriendStatusCard extends StatelessWidget {
  const FriendStatusCard({
    super.key,
    required this.friend,
    required this.tint,
    required this.pending,
    required this.accepted,
    required this.onKnock,
    this.doodle,
  });

  final HimaSession friend;
  final Color tint;

  /// My knock to this friend is still waiting for an answer.
  final bool pending;

  /// The knock was answered 「いいよ！」.
  final bool accepted;

  final VoidCallback onKnock;

  /// A small mark on some cards only, so the grid does not look gridded.
  final DoodleKind? doodle;

  @override
  Widget build(BuildContext context) {
    final activity = friend.activity;
    final style = activity == null ? null : ActivityStyle.of(activity);
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
              _MoodAvatar(friend: friend),
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
          Row(
            // spaceBetween instead of a Spacer: a Spacer would compete with the
            // tag for the flex space and squeeze the label for no reason.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: 3,
                  ),
                  // White rather than the activity tint: a card's tint rotates
                  // through the same pastels, so a tinted tag vanished on the
                  // card that happened to share its colour. The icon keeps the
                  // activity's own colour.
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        style?.icon ?? Icons.waving_hand_rounded,
                        size: 13,
                        color: style?.accent ?? AppColors.muted,
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      Flexible(
                        child: Text(
                          activity?.label ?? 'ひま',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (doodle != null) ...[
                const SizedBox(width: AppSpacing.s4),
                Doodle(
                  kind: doodle!,
                  size: const Size(14, 14),
                  color: doodle == DoodleKind.heart
                      ? AppColors.coral
                      : AppColors.yellow,
                  tilt: -0.25,
                  delay: const Duration(milliseconds: 160),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          KnockPill(
            friendName: friend.user.displayName,
            onTap: onKnock,
            sent: pending,
            accepted: accepted,
            expand: true,
          ),
        ],
      ),
    );
  }
}

/// The avatar with the friend's mood on its corner, the same language as the
/// hero so 「🔥」 means the same thing everywhere.
class _MoodAvatar extends StatelessWidget {
  const _MoodAvatar({required this.friend});

  final HimaSession friend;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        AvatarView(
          name: friend.user.displayName,
          imageUrl: friend.user.avatarUrl,
          size: 56,
          background: AppColors.surface.withValues(alpha: 0.85),
          ring: AppColors.surface,
        ),
        Positioned(
          right: -4,
          bottom: -4,
          child: Semantics(
            label: friend.mood.label,
            child: ExcludeSemantics(
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  friend.mood.emoji,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
