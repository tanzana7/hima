import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import 'paint/paint.dart';

/// 「さそう」, plus the states a knock can put it in.
///
/// Each state is a filled paint dab with readable text rather than a white pill
/// with a purple outline: the stroke was the last hairline on the home screen,
/// and a filled dab is what the rest of the screen is made of now.
///
/// The dab has no fixed height. At 200% text scale a fixed box clipped the
/// label vertically, so it keeps a minimum tap target and grows with the text
/// instead. Its seed comes from the friend's name, so one person's button keeps
/// the same silhouette across rebuilds and scrolling.
class KnockPill extends StatelessWidget {
  const KnockPill({
    super.key,
    required this.friendName,
    required this.onTap,
    this.sent = false,
    this.accepted = false,
    this.expand = false,
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

  @override
  Widget build(BuildContext context) {
    final locked = sent || accepted;
    // White on the primary purple is 6.3:1 and ink on the muted or mint dab is
    // above 12:1, so every state clears 4.5:1 without touching the text.
    final fill = accepted
        ? AppColors.mint
        : (sent ? AppColors.mutedSoft : AppColors.purple);
    final foreground = accepted || sent ? AppColors.ink : AppColors.surface;
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
          // The tap target stays 48dp while the visible dab is allowed to grow
          // past it.
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Center(
            child: PaintDab(
              seed: paintSeedOf('knock-$friendName'),
              color: fill,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              wobble: 0.035,
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: foreground),
                  const SizedBox(width: AppSpacing.s4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
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
    );
  }
}
