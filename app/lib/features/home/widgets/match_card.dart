import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/knock_pill.dart';
import '../../../shared/widgets/mood_badge.dart';
import '../../../shared/widgets/paint/paint.dart';

/// How the 🙂×🙂 match presents itself: the emoji pair in the header, the card's
/// pastel and the mark in its corner.
///
/// The tint is decoration only. What the card is about is written in the header
/// sentence, so a reader who cannot tell one pastel from another loses nothing.
const _matchEmoji = '🙂🙂';
const _matchTint = AppColors.skySoft;
const _matchAccent = AppColors.purple;
const _matchMark = PaintMarkKind.star;
const _matchMessage = 'お互い誘われ待ちだよ';

/// One card per match kind, shown between the hero and the friend grid.
///
/// A card per person flooded the screen and listed the same people the friend
/// grid below already shows, so the friends of a kind are grouped into one card
/// with a row of avatars.
///
/// The kind is stated once, by the emoji pair and the sentence in the header. An
/// earlier version floated a 🙂 bubble beside the first avatar, which read as
/// that person's mood instead of the kind's; each avatar now carries its own
/// mood badge, so every emoji on the card belongs to somebody.
///
/// The card takes the same pastel-and-ring language as the friend cards: a
/// white box with a thin border read as a form sitting next to the playful hero.
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

  /// Cell width at the default text scale. Wide enough for the 「さそった」 and
  /// 「いいよ！」 dabs, which are the longest labels the cell ever shows.
  static const _cellWidth = 100.0;

  /// How much wider a cell gets between 100% and 200% text scale. The cell only
  /// has to grow with the dab's label, not with the whole scale.
  static const _cellGrowth = 56.0;

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

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final visible = widget.matches.take(_maxAvatars).toList();
    final extra = widget.matches.length - visible.length;
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final cellWidth =
        _cellWidth + (textScale - 1).clamp(0.0, 1.0) * _cellGrowth;
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
        child: PaintWash(
          seed: paintSeedOf('match-${kind.name}'),
          color: _matchTint,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s12,
          ),
          corner: AppSpacing.radiusCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Decorative: the sentence beside it already says what the
                  // kind is, so a screen reader does not need the emoji read out.
                  ExcludeSemantics(
                    child: Text(
                      _matchEmoji,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 15, height: 1.2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      _matchMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.friendName.copyWith(fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  PaintMark(
                    kind: _matchMark,
                    seed: paintSeedOf('match-mark-${kind.name}'),
                    color: _matchAccent,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              _AvatarRow(
                cellWidth: cellWidth,
                children: [
                  for (final match in visible)
                    _FriendCell(
                      match: match,
                      width: cellWidth,
                      pending: widget.pendingUserIds.contains(
                        match.otherUser.id,
                      ),
                      accepted: widget.acceptedUserIds.contains(
                        match.otherUser.id,
                      ),
                      onTap: () => widget.onKnock(match),
                    ),
                  if (extra > 0) _MoreBadge(count: extra, width: cellWidth),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The avatars of one kind.
///
/// They spread across the card when they fit, because a handful of people
/// bunched against the left edge left the card looking half empty. Past that
/// they scroll instead of shrinking, since the dab under each avatar has to
/// stay readable.
class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.cellWidth, required this.children});

  /// Every child is exactly this wide, so the row can decide up front whether it
  /// fits without measuring anything.
  final double cellWidth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (children.length * cellWidth <= constraints.maxWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: children,
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.s8),
              children[index],
            ],
          ],
        ),
      );
    },
  );
}

/// One matched friend: a ringed avatar with their mood, their name and their own
/// knock dab.
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
              width: 56,
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The same white ring as the friend cards, so a person looks
                  // the same wherever they appear on the home screen.
                  AvatarView(
                    name: user.displayName,
                    imageUrl: user.avatarUrl,
                    size: 56,
                    background: AppColors.surface.withValues(alpha: 0.85),
                    ring: AppColors.surface,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: MoodBadge(mood: match.otherHima.mood),
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
          ),
        ],
      ),
    );
  }
}

/// 「+N」 for the friends of this kind that do not fit in the row.
class _MoreBadge extends StatelessWidget {
  const _MoreBadge({required this.count, required this.width});

  final int count;
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ほかに$count人',
    child: SizedBox(
      width: width,
      child: Center(
        child: PaintDab(
          seed: 71,
          color: AppColors.surface.withValues(alpha: 0.94),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: 6),
          wobble: 0.11,
          child: Text(
            '+$count',
            maxLines: 1,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ),
  );
}
