import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/avatar_view.dart';
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
      messenger.showSnackBar(const SnackBar(content: Text('さそったよ')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppHaptics.error();
      _shakeKey.currentState?.shake();
      messenger.showSnackBar(
        const SnackBar(content: Text('さそえなかった。もう一度試してね')),
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
            child: SizedBox(
              height: 56,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: FilledButton(
                      onPressed: _sending ? null : _send,
                      child: const Text('さそう'),
                    ),
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
          ),
        ],
      ),
    );
  }
}

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
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.minTapTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.purpleSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? AppColors.purple : AppColors.purpleSoft,
            width: AppSpacing.borderWidth,
          ),
        ),
        child: Center(
          child: Text(
            template.text,
            style: AppTextStyles.body.copyWith(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}
