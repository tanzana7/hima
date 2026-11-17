import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/models/models.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/avatar_view.dart';
import '../../shared/widgets/brush_title.dart';
import '../../shared/widgets/confetti_burst.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/paint/paint.dart';
import '../../shared/widgets/paint_button.dart';
import '../../state/app_view_model.dart';

/// Captions that sit directly on a [PaintWash]. [AppColors.muted] measures
/// 4.2:1 on the pastel wash, so text on paint takes this darker tone instead
/// (5.4:1).
const _washMuted = Color(0xFF635B6F);

/// Knocks inbox and sent list, reached from the header bell.
class KnocksScreen extends StatefulWidget {
  const KnocksScreen({super.key, this.showSentFirst = false});

  /// Opens on the 送信 tab, used when the user taps a reply celebration.
  final bool showSentFirst;

  @override
  State<KnocksScreen> createState() => _KnocksScreenState();
}

class _KnocksScreenState extends State<KnocksScreen> {
  late bool _showSent = widget.showSentFirst;
  final Set<String> _markingSeen = {};
  final Set<String> _highlighted = {};
  bool _showConfetti = false;
  int _confettiToken = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewModel = context.read<AppViewModel>();
    if (_showSent) {
      _celebrateNewResults(viewModel);
    } else {
      _markInboxSeenAfterDisplay(viewModel);
    }
  }

  /// Showing the inbox clears the bell dot; the knock itself stays pending
  /// until it is answered.
  void _markInboxSeenAfterDisplay(AppViewModel viewModel) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_showSent) viewModel.markInboxSeen();
    });
  }

  /// 「いいよ！」 arriving is celebrated once per knock across the app (Home
  /// may have shown it first); the highlight stays per visit.
  void _celebrateNewResults(AppViewModel viewModel) {
    final fresh = viewModel.sent
        .where(
          (knock) =>
              knock.status == KnockStatus.accepted &&
              knock.resultSeenAt == null &&
              _highlighted.add(knock.id),
        )
        .toList();
    if (fresh.isEmpty) return;
    final celebrate = fresh
        .where((knock) => viewModel.claimResultCelebration(knock.id))
        .toList();
    if (celebrate.isEmpty) return;
    AppHaptics.celebrate();
    _confettiToken++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showConfetti = true);
    });
  }

  /// Results stay highlighted for this visit, then are marked seen on the
  /// server so the header badge clears.
  void _markUnseenAfterDisplay(List<Knock> knocks, AppViewModel viewModel) {
    final unseen = knocks
        .where(
          (knock) =>
              knock.status != KnockStatus.pending &&
              knock.resultSeenAt == null &&
              _markingSeen.add(knock.id),
        )
        .map((knock) => knock.id)
        .toList();
    if (unseen.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showSent) {
        _markingSeen.removeAll(unseen);
        return;
      }
      for (final id in unseen) {
        unawaited(
          viewModel.markKnockResultSeen(id).catchError((Object _) {
            _markingSeen.remove(id);
          }),
        );
      }
    });
  }

  Future<void> _respond(String id, KnockStatus response) async {
    final viewModel = context.read<AppViewModel>();
    try {
      await viewModel.respondToKnock(id, response);
      if (!mounted) return;
      AppHaptics.select();
    } catch (_) {
      if (!mounted) return;
      AppHaptics.error();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('返事を送れなかった。もう一度試してね')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    if (_showSent) _markUnseenAfterDisplay(viewModel.sent, viewModel);
    final knocks = _showSent ? viewModel.sent : viewModel.inbox;
    return Scaffold(
      // No title spacing: the title sits right after the back button instead of
      // leaving the default 16dp gap on top of the 56dp leading slot.
      appBar: AppBar(
        titleSpacing: 0,
        // The title carries the same brush stroke as the tab headers, so the
        // toolbar has to grow with the text scale or the stroke is clipped.
        toolbarHeight: BrushTitle.toolbarHeight(context),
        title: const BrushTitle(title: 'ノック', seed: 83),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s8,
              AppSpacing.s16,
              AppSpacing.s32,
            ),
            children: [
              _Toggle(
                showSent: _showSent,
                onChanged: (value) {
                  AppHaptics.select();
                  setState(() => _showSent = value);
                  if (value) {
                    _celebrateNewResults(viewModel);
                  } else {
                    _markInboxSeenAfterDisplay(viewModel);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.s16),
              if (knocks.isEmpty)
                EmptyState(
                  message: _showSent ? 'まださそってないよ' : '届いたノックはないよ',
                  icon: Icons.notifications_none_rounded,
                )
              else
                for (final knock in knocks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                    child: _KnockCard(
                      knock: knock,
                      sent: _showSent,
                      highlighted: _highlighted.contains(knock.id),
                      onRespond: (status) => _respond(knock.id, status),
                    ),
                  ),
            ],
          ),
          if (_showConfetti)
            Positioned.fill(
              child: ConfettiBurst(
                key: ValueKey(_confettiToken),
                onCompleted: () {
                  if (mounted) setState(() => _showConfetti = false);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 受信 / 送信. There is no pale track and no white pill: the selected segment
/// gets a purple dab that splashes in, and the other one is plain text on the
/// paper.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.showSent, required this.onChanged});

  final bool showSent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ToggleItem(
          label: '受信',
          selected: !showSent,
          onTap: () => onChanged(false),
        ),
      ),
      Expanded(
        child: _ToggleItem(
          label: '送信',
          selected: showSent,
          onTap: () => onChanged(true),
        ),
      ),
    ],
  );
}

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The label's box, shared by both states so the text does not shift when the
  /// dab moves between the segments.
  static const _labelPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.s24,
    vertical: AppSpacing.s8,
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    // The child's semantics are excluded, so the wrapper has to carry the
    // action itself or the segment cannot be activated by a screen reader.
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Center(
          child: selected
              ? TweenAnimationBuilder<double>(
                  // The dab lands with a small overshoot. It only ever grows
                  // past its resting size, so the white label never leaves the
                  // paint while it settles.
                  tween: Tween(begin: 0, end: 1),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  builder: (context, t, child) => Transform.scale(
                    scale: 1 + 0.06 * math.sin(math.pi * t),
                    child: child,
                  ),
                  child: PaintDab(
                    seed: paintSeedOf('knocks-tab-$label'),
                    color: AppColors.purple,
                    padding: _labelPadding,
                    wobble: 0.04,
                    droplets: 2,
                    child: Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.surface,
                      ),
                    ),
                  ),
                )
              : Padding(
                  padding: _labelPadding,
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}

class _KnockCard extends StatelessWidget {
  const _KnockCard({
    required this.knock,
    required this.sent,
    required this.highlighted,
    required this.onRespond,
  });

  final Knock knock;
  final bool sent;
  final bool highlighted;
  final ValueChanged<KnockStatus> onRespond;

  @override
  Widget build(BuildContext context) {
    final person =
        (sent ? knock.recipient : knock.sender) ??
        const UserSummary(id: '', displayName: '友達');
    final isNew =
        sent &&
        knock.status != KnockStatus.pending &&
        (highlighted || knock.resultSeenAt == null);
    // 「返事待ち」 would read as if I were waiting on a knock I received, so a
    // received knock shows when it arrived until I answer it.
    final statusText = sent
        ? knock.status.label
        : knock.status == KnockStatus.pending
        ? _relativeTime(knock.createdAt, DateTime.now())
        : _answeredLabel(knock.status);
    // A wash instead of a bordered white box: the paint is the card's edge, so
    // there is no hairline to separate it from the page. A new reply keeps the
    // peach tint and the 新着 dab rather than a coral border, because a coral
    // wash would drop the caption text below 4.5:1.
    return PaintWash(
      seed: paintSeedOf('knock-${knock.id}'),
      color: isNew ? AppColors.peachSoft : AppColors.purpleSoft,
      padding: const EdgeInsets.all(AppSpacing.s16),
      corner: AppSpacing.radiusCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarView(
                name: person.displayName,
                imageUrl: person.avatarUrl,
                size: 42,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.friendName.copyWith(fontSize: 15),
                    ),
                    Text(
                      knock.template.text,
                      maxLines: 2,
                      style: AppTextStyles.caption.copyWith(color: _washMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isNew)
                    PaintDab(
                      seed: paintSeedOf('knock-new-${knock.id}'),
                      color: AppColors.coral,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                        vertical: 3,
                      ),
                      wobble: 0.05,
                      child: Text(
                        '新着',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Text(
                    statusText,
                    style: AppTextStyles.caption.copyWith(
                      color: isNew ? AppColors.ink : _washMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!sent && knock.recipientNote != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              knock.recipientNote!,
              style: AppTextStyles.caption.copyWith(color: _washMuted),
            ),
          ],
          if (!sent && knock.status == KnockStatus.pending) ...[
            const SizedBox(height: AppSpacing.s12),
            _ReplyButtons(onRespond: onRespond),
          ],
        ],
      ),
    );
  }
}

/// Relative arrival time for a received knock that is still waiting for me.
String _relativeTime(DateTime createdAt, DateTime now) {
  final elapsed = now.difference(createdAt);
  if (elapsed.inMinutes < 1) return 'たった今';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}分前';
  if (elapsed.inDays < 1) return '${elapsed.inHours}時間前';
  if (elapsed.inDays < 7) return '${elapsed.inDays}日前';
  final local = createdAt.toLocal();
  return '${local.month}月${local.day}日';
}

/// A received knock I already answered reads as what I did, not as the label of
/// the button I pressed.
String _answeredLabel(KnockStatus status) => switch (status) {
  KnockStatus.accepted => 'いいよ！した',
  KnockStatus.later => 'あとで返した',
  KnockStatus.passed => 'パスした',
  // An unanswered knock expires instead of being answered, so this only shows
  // the status name.
  KnockStatus.expired => KnockStatus.expired.label,
  KnockStatus.pending => KnockStatus.pending.label,
};

/// The three replies share one row of equal widths. They stack full width when
/// the card is too narrow for the widest label at the current text size, so no
/// label ever wraps into an uneven second row or gets clipped.
class _ReplyButtons extends StatelessWidget {
  const _ReplyButtons({required this.onRespond});

  final ValueChanged<KnockStatus> onRespond;

  /// 「今回はパス」 is the widest label: 5 full-width glyphs at [_labelSize].
  static const double _labelSize = 15;
  static const int _widestLabelGlyphs = 5;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale =
          MediaQuery.textScalerOf(context).scale(_labelSize) / _labelSize;
      final labelWidth = _widestLabelGlyphs * _labelSize * textScale;
      final buttonWidth = labelWidth + AppSpacing.s8 * 2;
      final stacked =
          constraints.maxWidth < buttonWidth * 3 + AppSpacing.s8 * 2;
      final buttons = [
        _button(KnockStatus.accepted, 'いいよ！', filled: true),
        _button(KnockStatus.later, 'あとで'),
        _button(KnockStatus.passed, '今回はパス'),
      ];
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < buttons.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.s8),
              buttons[index],
            ],
          ],
        );
      }
      return Row(
        children: [
          for (var index = 0; index < buttons.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.s8),
            Expanded(child: buttons[index]),
          ],
        ],
      );
    },
  );

  Widget _button(KnockStatus status, String label, {bool filled = false}) {
    // Equal thirds of a card are narrow, so the dab's padding and label are
    // trimmed back for these three. 「いいよ！」 is the primary answer and takes
    // the purple dab with white text; the other two are a soft tint with ink.
    // The tint is sky, not the card's own lavender or peach: a dab of the wash's
    // hue disappears into it, and mint is already the colour of an accepted
    // knock.
    final style = AppTextStyles.button.copyWith(fontSize: _labelSize);
    return PaintButton(
      seed: paintSeedOf('knock-reply-${status.name}'),
      label: label,
      color: filled ? AppColors.purple : AppColors.skySoft,
      foreground: filled ? AppColors.surface : AppColors.ink,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s12,
      ),
      textStyle: style,
      onPressed: () => onRespond(status),
    );
  }
}
