import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/knock_pill.dart';

/// Match card shown between the hero and the friend grid.
///
/// It springs in once. For ok × ok the two avatars slide together and bump,
/// which is the visual for 「お互い誘われ待ちだよ」.
class MatchCard extends StatefulWidget {
  const MatchCard({
    super.key,
    required this.match,
    required this.me,
    required this.onKnock,
  });

  final MatchRecord match;
  final UserProfile me;
  final VoidCallback onKnock;

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard>
    with SingleTickerProviderStateMixin {
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

  String get _message => switch (widget.match.kind) {
    MatchKind.fireFire => 'いっしょに遊べる人がいるよ',
    MatchKind.fireOk => '誘えば来る人がいるよ',
    MatchKind.okOk => 'お互い誘われ待ちだよ',
  };

  @override
  Widget build(BuildContext context) {
    final other = widget.match.otherUser;
    final activity = widget.match.otherHima.activity;
    final detail = activity == null
        ? '${other.displayName} · ひま'
        : '${other.displayName} · ${activity.label}';
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatars(context),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.friendName.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s4),
                        KnockPill(
                          friendName: other.displayName,
                          onTap: widget.onKnock,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatars(BuildContext context) {
    final other = widget.match.otherUser;
    if (widget.match.kind != MatchKind.okOk) {
      return AvatarView(
        name: other.displayName,
        imageUrl: other.avatarUrl,
        size: 44,
        background: AppColors.purpleSoft,
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final close = CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.35, 0.95, curve: Curves.easeOutBack),
        ).value;
        // Ends slightly overlapped so the two heads "bump" but stay readable.
        final gap = 14 + 10 * (1 - close);
        return SizedBox(
          width: 84,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 42 - gap - 15,
                top: 7,
                child: AvatarView(
                  name: widget.me.displayName,
                  imageUrl: widget.me.avatarUrl,
                  size: 30,
                  background: AppColors.yellow,
                ),
              ),
              Positioned(
                left: 42 + gap - 15,
                top: 7,
                child: AvatarView(
                  name: other.displayName,
                  imageUrl: other.avatarUrl,
                  size: 30,
                  background: AppColors.purpleSoft,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
