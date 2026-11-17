import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/api_client.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/avatar_view.dart';
import '../../../shared/widgets/paint/paint.dart';
import '../../../shared/widgets/paint_button.dart';
import '../../../shared/widgets/shake.dart';
import '../../../state/app_view_model.dart';

Future<void> showKnockSheet(
  BuildContext context, {
  required UserSummary user,
  Activity? activity,
  Mood? mood,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => KnockSheet(
    user: user,
    activity: activity,
    quiet: mood == Mood.quiet,
  ),
);

/// さそう sheet: pick one of the three fixed templates and send an in-app knock.
class KnockSheet extends StatefulWidget {
  const KnockSheet({
    super.key,
    required this.user,
    required this.quiet,
    this.activity,
  });

  final UserSummary user;
  final bool quiet;
  final Activity? activity;

  @override
  State<KnockSheet> createState() => _KnockSheetState();
}

class _KnockSheetState extends State<KnockSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flight;
  final GlobalKey<ShakeState> _shakeKey = GlobalKey<ShakeState>();
  KnockTemplate _template = KnockTemplate.game;
  bool _sending = false;
  bool _flying = false;

  @override
  void initState() {
    super.initState();
    // Eager so dispose() never has to build a Ticker (reduced motion skips the
    // flight entirely, leaving a lazy controller untouched).
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final viewModel = context.read<AppViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await viewModel.sendKnock(widget.user.id, _template);
      if (!mounted) return;
      AppHaptics.send();
      if (!MediaQuery.disableAnimationsOf(context)) {
        setState(() => _flying = true);
        await _flight.forward(from: 0);
      }
      if (!mounted) return;
      navigator.pop();
      // No success SnackBar: the paper plane and the 「さそった」 pill the sheet
      // leaves behind already say the knock went out, so a third confirmation
      // would only cover the friend list. Errors still get one below.
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppHaptics.error();
      _shakeKey.currentState?.shake();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            // A 409 means the 5 minute per-pair cooldown is still running; the
            // client already phrases that for the user.
            error is ApiException && error.statusCode == 409
                ? error.message
                : 'さそえなかった。もう一度試してね',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s24,
        0,
        AppSpacing.s24,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AvatarView(
                name: widget.user.displayName,
                imageUrl: widget.user.avatarUrl,
                size: 44,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.friendName,
                    ),
                    Text(
                      activity == null ? 'ひま' : activity.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final template in KnockTemplate.values)
                _TemplateChip(
                  template: template,
                  selected: _template == template,
                  onTap: () {
                    AppHaptics.select();
                    setState(() => _template = template);
                  },
                ),
            ],
          ),
          if (widget.quiet) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              'スルーしてOK',
              style: AppTextStyles.caption.copyWith(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: AppSpacing.s24),
          Shake(
            key: _shakeKey,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // A big purple dab instead of a stadium button: the sheet's
                // send action is the same paint as the home screen's primary.
                // It has no fixed height, so the label still fits at 200% text
                // scale.
                PaintButton(
                  seed: 5150,
                  label: 'さそう',
                  color: AppColors.purple,
                  foreground: AppColors.surface,
                  minHeight: 56,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s24,
                    vertical: AppSpacing.s16,
                  ),
                  textStyle: AppTextStyles.button.copyWith(fontSize: 17),
                  onPressed: _sending ? null : _send,
                ),
                if (_flying)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _flight,
                        builder: (context, child) {
                          final t = _flight.value;
                          return Align(
                            alignment: Alignment(
                              -0.4 + t * 2.2,
                              -0.1 - t * 1.8,
                            ),
                            child: Opacity(
                              opacity: (1 - t).clamp(0.0, 1.0),
                              child: Transform.rotate(
                                angle: t * 1.1,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: const Icon(
                          Icons.send_rounded,
                          size: 22,
                          color: AppColors.purple,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the three fixed templates as a selectable dab: the chosen one is the
/// saturated purple with white text, the others a soft tint with ink. The fill
/// swaps in one step rather than tweening, because a half-faded fill would put
/// the label below 4.5:1 for the length of the animation.
class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final KnockTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: template.text,
    // The child's semantics are excluded, so the wrapper has to carry the
    // action itself or the chip cannot be activated by a screen reader.
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: PaintDab(
        seed: paintSeedOf('knock-template-${template.name}'),
        color: selected ? AppColors.purple : AppColors.purpleSoft,
        // 14dp of vertical padding brings the dab to the 48dp tap target
        // without a fixed height, so it still grows with the text.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: 14,
        ),
        wobble: 0.045,
        droplets: selected ? 2 : 0,
        child: Text(
          template.text,
          style: AppTextStyles.body.copyWith(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? AppColors.surface : AppColors.ink,
          ),
        ),
      ),
    ),
  );
}
