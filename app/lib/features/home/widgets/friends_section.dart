import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/decorations.dart';
import '../../../shared/widgets/empty_state.dart';
import 'friend_status_card.dart';

/// 「いまひまな友達」 with the lime count badge and a responsive grid.
class FriendsSection extends StatelessWidget {
  const FriendsSection({
    super.key,
    required this.friends,
    required this.pendingUserIds,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onKnock,
  });

  final List<HimaSession> friends;

  /// People whose knock from me is still waiting for an answer.
  final Set<String> pendingUserIds;

  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;
  final ValueChanged<HimaSession> onKnock;

  /// Two columns need this much width for the 56dp avatar plus the name, the
  /// status and the remaining time next to it.
  static const _twoColumnMinWidth = 348.0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'いまひまな友達',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.sectionTitle,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          _CountBadge(count: friends.length),
          const SizedBox(width: AppSpacing.s8),
          const StarAccent(size: 18),
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
            // remaining time and the さそう pill never overlap.
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s8,
      vertical: 2,
    ),
    decoration: BoxDecoration(
      color: AppColors.lime,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
    ),
    child: Text(
      '$count人',
      style: AppTextStyles.caption.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
