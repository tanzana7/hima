import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/knock_pill.dart';
import '../../../shared/widgets/mood_badge.dart';
import '../../../shared/widgets/paint/paint.dart';
import '../hero_state.dart';

/// One friend in the home grid: a large ringed avatar, name and remaining time,
/// a small dab for what they want to do, and さそう across the bottom.
///
/// The background is a [PaintWash] instead of a bordered pastel box: the wash
/// is the card's edge, so there is no hairline to separate it from the page.
/// Its seed comes from the friend's id, so a card keeps the same silhouette
/// across rebuilds, polls and scrolling, and the hue still rotates per card and
/// carries no meaning — the state is always written out in text as well.
class FriendStatusCard extends StatelessWidget {
  const FriendStatusCard({
    super.key,
    required this.friend,
    required this.tint,
    required this.pending,
    required this.accepted,
    required this.onKnock,
    this.mark,
  });

  final HimaSession friend;
  final Color tint;

  /// My knock to this friend is still waiting for an answer.
  final bool pending;

  /// The knock was answered 「いいよ！」.
  final bool accepted;

  final VoidCallback onKnock;

  /// A small mark on some cards only, so the grid does not look gridded.
  final PaintMarkKind? mark;

  @override
  Widget build(BuildContext context) {
    final activity = friend.activity;
    final style = activity == null ? null : ActivityStyle.of(activity);
    return PaintWash(
      seed: paintSeedOf(friend.user.id),
      color: tint,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
      corner: AppSpacing.radiusCard,
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
                child: PaintDab(
                  seed: paintSeedOf('tag-${friend.sessionId}'),
                  // White rather than the activity tint: a card's wash rotates
                  // through the same pastels, so a tinted dab vanished on the
                  // card that happened to share its colour. The icon keeps the
                  // activity's own colour.
                  color: AppColors.surface.withValues(alpha: 0.94),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: 4,
                  ),
                  wobble: 0.12,
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
              if (mark != null) ...[
                const SizedBox(width: AppSpacing.s4),
                PaintMark(
                  kind: mark!,
                  seed: paintSeedOf('mark-${friend.user.id}'),
                  color: mark == PaintMarkKind.heart
                      ? AppColors.coral
                      : AppColors.yellow,
                  size: 14,
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
/// hero so a mood reads the same everywhere.
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
          child: MoodBadge(mood: friend.mood),
        ),
      ],
    ),
  );
}
