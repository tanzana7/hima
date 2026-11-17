import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/knock_pill.dart';

/// One card per match kind, shown between the hero and the friend grid.
///
/// A card per person flooded the screen (four separate cards with 🔥) and listed
/// the same people the friend grid below already shows, so the friends of a kind
/// are grouped into one card with a row of avatars.
///
/// The kind is stated once, by the icon and the sentence in the header. An
/// earlier version floated a 🙂 bubble beside the first avatar, which read as
/// that person's mood instead of the kind's; each avatar now carries its own
/// mood badge, so every emoji on the card belongs to somebody.
class MatchCard extends StatefulWidget {
  const MatchCard({
    super.key,
    required this.kind,
    required this.matches,
    required this.pendingUserIds,
    required this.acceptedUserIds,
    required this.onKnock,
  });

  final MatchKind kind;

  /// Every matched friend of this kind.
  final List<MatchRecord> matches;

  /// People whose knock from me is still waiting for an answer.
  final Set<String> pendingUserIds;

  /// People whose knock was answered 「いいよ！」.
  final Set<String> acceptedUserIds;

  final ValueChanged<MatchRecord> onKnock;

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard>
    with SingleTickerProviderStateMixin {
  /// Beyond this the row would only be scrolled, so the rest is summarised.
  static const _maxAvatars = 5;

  /// Cell width at the default text scale; wider text scales the cell up.
  static const _cellWidth = 72.0;

  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _message => switch (widget.kind) {
    MatchKind.fireFire => 'いっしょに遊べる人がいるよ',
    MatchKind.fireOk => '誘えば来る人がいるよ',
    MatchKind.okOk => 'お互い誘われ待ちだよ',
  };

  IconData get _icon => switch (widget.kind) {
    MatchKind.fireFire => Icons.local_fire_department_rounded,
    MatchKind.fireOk => Icons.bolt_rounded,
    MatchKind.okOk => Icons.people_alt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final visible = widget.matches.take(_maxAvatars).toList();
    final extra = widget.matches.length - visible.length;
    // The cell grows with the text scale: a fixed 72dp cell squeezed 「さそう」
    // into an ellipsis at 200%. Scaling by the same factor as the label keeps
    // the pill readable at any size.
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final cellWidth = _cellWidth * (textScale < 1 ? 1.0 : textScale);
    final appearance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.7, curve: Curves.easeOutBack),
    );
    final opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
    );

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.12, 0.25),
          end: Offset.zero,
        ).animate(appearance),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s12 + 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            border: Border.all(
              color: AppColors.purpleSoft,
              width: AppSpacing.borderWidth,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon, size: 16, color: AppColors.purple),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: Text(
                      _message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.friendName.copyWith(fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < visible.length; index++) ...[
                      if (index > 0) const SizedBox(width: AppSpacing.s8),
                      _FriendCell(
                        match: visible[index],
                        width: cellWidth,
                        pending: widget.pendingUserIds.contains(
                          visible[index].otherUser.id,
                        ),
                        accepted: widget.acceptedUserIds.contains(
                          visible[index].otherUser.id,
                        ),
                        onTap: () => widget.onKnock(visible[index]),
                      ),
                    ],
                    if (extra > 0) ...[
                      const SizedBox(width: AppSpacing.s8),
                      _MoreBadge(count: extra),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One matched friend: avatar with their mood, name and its own knock pill.
class _FriendCell extends StatelessWidget {
  const _FriendCell({
    required this.match,
    required this.width,
    required this.pending,
    required this.accepted,
    required this.onTap,
  });

  final MatchRecord match;
  final double width;
  final bool pending;
  final bool accepted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final user = match.otherUser;
    final locked = pending || accepted;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: locked ? null : onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarView(
                    name: user.displayName,
                    imageUrl: user.avatarUrl,
                    // 48dp keeps the avatar itself a valid tap target.
                    size: 48,
                    background: AppColors.purpleSoft,
                    ring: AppColors.surface,
                    ringWidth: 2,
                  ),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Semantics(
                      label: match.otherHima.mood.label,
                      child: ExcludeSemantics(
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            match.otherHima.mood.emoji,
                            style: const TextStyle(fontSize: 9),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          KnockPill(
            friendName: user.displayName,
            onTap: onTap,
            sent: pending,
            accepted: accepted,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// 「+N」 for the friends of this kind that do not fit in the row.
class _MoreBadge extends StatelessWidget {
  const _MoreBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ほかに$count人',
    child: Container(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.purpleSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        '+$count',
        maxLines: 1,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}
