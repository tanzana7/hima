import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/paint/paint.dart';
import 'friend_status_card.dart';

/// 「いまひまな友達」 with an icon, the lime count dab, a brush-stroke underline
/// and a responsive grid.
class FriendsSection extends StatelessWidget {
  const FriendsSection({
    super.key,
    required this.friends,
    required this.pendingUserIds,
    required this.acceptedUserIds,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onKnock,
  });

  final List<HimaSession> friends;

  /// People whose knock from me is still waiting for an answer.
  final Set<String> pendingUserIds;

  /// People whose knock was answered 「いいよ！」.
  final Set<String> acceptedUserIds;

  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;
  final ValueChanged<HimaSession> onKnock;

  /// Two columns need this much width for the 56dp avatar plus the name, the
  /// status and the remaining time next to it.
  static const _twoColumnMinWidth = 348.0;

  /// Only some cards get a mark, so the grid does not look gridded.
  static PaintMarkKind? _markFor(int index) => switch (index % 4) {
    1 => PaintMarkKind.heart,
    3 => PaintMarkKind.star,
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.group_rounded, size: 22, color: AppColors.ink),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'いまひまな友達',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle,
                ),
                // A brush stroke, not a thin squiggle: the underline is paint
                // now, thick in the middle and tapering at both ends.
                BrushStroke(
                  seed: 31,
                  size: const Size(120, 9),
                  color: AppColors.purple.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          _CountBadge(count: friends.length),
          const SizedBox(width: AppSpacing.s8),
          const SplatterDots(
            seed: 47,
            size: Size(22, 18),
            color: AppColors.coral,
            count: 5,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.s12),
      if (friends.isEmpty)
        if (loading)
          const LoadingState()
        else if (hasError)
          EmptyState(
            message: '友達を読み込めなかったよ',
            icon: Icons.cloud_off_rounded,
            action: TextButton(onPressed: onRetry, child: const Text('もう一度')),
          )
        else
          const EmptyState(message: 'まだひまな友達はいないよ')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            // Narrow screens and large text switch to one column so names, the
            // remaining time and the さそう dab never overlap.
            final columns =
                constraints.maxWidth < _twoColumnMinWidth || textScale > 1.3
                ? 1
                : 2;
            final gap = AppSpacing.s12;
            final itemWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - gap) / 2;
            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            return AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Wrap(
                key: ValueKey(
                  friends.map((friend) => friend.sessionId).join('|'),
                ),
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var index = 0; index < friends.length; index++)
                    SizedBox(
                      width: itemWidth,
                      child: FriendStatusCard(
                        friend: friends[index],
                        tint:
                            AppColors.friendTints[index %
                                AppColors.friendTints.length],
                        pending: pendingUserIds.contains(friends[index].user.id),
                        accepted: acceptedUserIds.contains(
                          friends[index].user.id,
                        ),
                        mark: _markFor(index),
                        onKnock: () => onKnock(friends[index]),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
    ],
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => PaintDab(
    seed: 53,
    color: AppColors.lime,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: 3),
    wobble: 0.05,
    child: Text(
      '$count人',
      style: AppTextStyles.caption.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
