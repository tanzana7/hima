import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/paint/paint.dart';

/// Small mood picker opened from the declared avatar badge.
Future<Mood?> showMoodPicker(BuildContext context, {required Mood current}) =>
    showModalBottomSheet<Mood>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s24,
          0,
          AppSpacing.s24,
          AppSpacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('温度感', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.s12),
            for (final mood in Mood.values)
              _ChoiceTile(
                label: '${mood.emoji} ${mood.label}',
                selected: mood == current,
                onTap: () => Navigator.of(sheetContext).pop(mood),
              ),
          ],
        ),
      ),
    );

/// A selected activity, an explicit clear, or dismissal without a change.
///
/// Keeping null inside a choice distinguishes clearing from closing the picker.
class ActivityChoice {
  const ActivityChoice(this.activity);

  final Activity? activity;
}

/// The hero's inline activity picker. The five server-supported activities are
/// rendered as paint blobs; selecting one returns the hero to its prior state.
class InlineActivityPicker extends StatefulWidget {
  const InlineActivityPicker({
    super.key,
    required this.current,
    required this.originGlobal,
    required this.onSelected,
    required this.onClose,
  });

  final Activity? current;
  final Offset? originGlobal;
  final ValueChanged<ActivityChoice> onSelected;
  final VoidCallback onClose;

  @override
  State<InlineActivityPicker> createState() => _InlineActivityPickerState();
}

class _InlineActivityPickerState extends State<InlineActivityPicker>
    with TickerProviderStateMixin {
  static const _popDuration = Duration(milliseconds: 620);
  static const _commitDuration = Duration(milliseconds: 180);

  late final AnimationController _pop;
  late final AnimationController _commit;
  Activity? _committing;
  Offset? _originGlobal;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: _popDuration);
    _commit = AnimationController(vsync: this, duration: _commitDuration);
    _originGlobal = widget.originGlobal;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_originGlobal == null) {
        final box = context.findRenderObject();
        if (box is RenderBox && box.hasSize) {
          _originGlobal = box.localToGlobal(Offset(box.size.width / 2, 28));
        }
      }
      if (_reduceMotion) {
        _pop.value = 1;
      } else {
        _pop.forward();
      }
    });
  }

  @override
  void didUpdateWidget(InlineActivityPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originGlobal != widget.originGlobal) {
      _originGlobal = widget.originGlobal;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    _commit.dispose();
    super.dispose();
  }

  void _choose(ActivityChoice choice) {
    AppHaptics.select();
    if (_reduceMotion) {
      widget.onSelected(choice);
      return;
    }
    setState(() => _committing = choice.activity);
    _commit.forward(from: 0).whenComplete(() {
      if (mounted) widget.onSelected(choice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final oneColumn = scale > 1.25;
    final activities = Activity.values;
    final rows = <List<Activity>>[];
    for (var i = 0; i < activities.length; i += oneColumn ? 1 : 2) {
      rows.add(activities.skip(i).take(oneColumn ? 1 : 2).toList());
    }

    return PaintThick(
      seed: 6011,
      colors: const [Color(0xFFFFEAF3), Color(0xFFFFD8E9)],
      padding: const EdgeInsets.all(18),
      wobble: 0.045,
      droplets: 12,
      drips: 0,
      arms: 4,
      armLength: 0.035,
      bristles: false,
      dryEdge: false,
      gloss: 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('なにする？', style: AppTextStyles.sectionTitle),
              ),
              IconButton(
                tooltip: '閉じる',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final row in rows) ...[
            if (row.length == 1 && !oneColumn)
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.72,
                  child: _activityBlob(row.single),
                ),
              )
            else
              Row(
                children: [
                  Expanded(child: _activityBlob(row.first)),
                  if (row.length == 2) ...[
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(child: _activityBlob(row.last)),
                  ],
                ],
              ),
            const SizedBox(height: AppSpacing.s8),
          ],
          if (widget.current != null) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _choose(const ActivityChoice(null)),
                icon: const Icon(Icons.remove_circle_outline_rounded),
                label: const Text('選択を解除'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activityBlob(Activity activity) => _ActivityPaintBlob(
    activity: activity,
    selected: activity == widget.current,
    committing: _committing == activity,
    index: Activity.values.indexOf(activity),
    pop: _pop,
    commit: _commit,
    originGlobal: _originGlobal,
    reduceMotion: _reduceMotion,
    onTap: () => _choose(ActivityChoice(activity)),
  );
}

class _ActivityPaintBlob extends StatelessWidget {
  const _ActivityPaintBlob({
    required this.activity,
    required this.selected,
    required this.committing,
    required this.index,
    required this.pop,
    required this.commit,
    required this.originGlobal,
    required this.reduceMotion,
    required this.onTap,
  });

  final Activity activity;
  final bool selected;
  final bool committing;
  final int index;
  final Animation<double> pop;
  final Animation<double> commit;
  final Offset? originGlobal;
  final bool reduceMotion;
  final VoidCallback onTap;

  Color get _fill => switch (activity) {
    Activity.game => AppColors.yellow,
    Activity.chat => const Color(0xFF54BDE8),
    Activity.work => const Color(0xFF983FD0),
    Activity.out => const Color(0xFF91D96F),
    Activity.any => const Color(0xFFFFB19F),
  };

  @override
  Widget build(BuildContext context) {
    final style = ActivityStyle.of(activity);
    final textColor = activity == Activity.work
        ? AppColors.surface
        : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: activity.label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: AnimatedBuilder(
            animation: Listenable.merge([pop, commit]),
            builder: (context, child) {
              final start = index * 0.075;
              final phase = reduceMotion
                  ? 1.0
                  : Interval(start, 0.92).transform(pop.value);
              final landed = reduceMotion
                  ? 1.0
                  : Curves.elasticOut.transform(phase);
              final box = context.findRenderObject();
              final target = box is RenderBox && box.hasSize
                  ? box.localToGlobal(box.size.center(Offset.zero))
                  : (originGlobal ?? Offset.zero);
              final origin = originGlobal ?? target;
              final commitT = committing && !reduceMotion ? commit.value : 0.0;
              return Transform.translate(
                offset: (origin - target) * (1 - phase),
                child: Transform.scale(
                  scale:
                      (0.35 + 0.65 * landed + (selected ? 0.08 : 0)) *
                      (1 + commitT * 0.42),
                  child: Opacity(opacity: 1 - commitT, child: child),
                ),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PaintThick(
                  seed: paintSeedOf('inline-activity-${activity.name}'),
                  colors: [Color.lerp(_fill, Colors.white, 0.24)!, _fill],
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: selected ? 16 : 13,
                  ),
                  wobble: 0.09,
                  droplets: selected ? 3 : 2,
                  drips: 0,
                  arms: 0,
                  gloss: 0.65,
                  bristles: false,
                  dryEdge: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(style.icon, size: 20, color: textColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          activity.label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Positioned(
                    right: -2,
                    top: -3,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 23,
                          color: activity == Activity.work
                              ? _fill
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline slider preview. Dragging snaps to the app's three supported
/// durations; releasing commits, while closing leaves the saved value alone.
class InlineDurationPicker extends StatefulWidget {
  const InlineDurationPicker({
    super.key,
    required this.current,
    required this.onCommit,
    required this.onClose,
  });

  final int current;
  final ValueChanged<int> onCommit;
  final VoidCallback onClose;

  @override
  State<InlineDurationPicker> createState() => _InlineDurationPickerState();
}

class _InlineDurationPickerState extends State<InlineDurationPicker> {
  late int _preview = widget.current;

  int get _index => himaDurationChoices
      .indexOf(_preview)
      .clamp(0, himaDurationChoices.length - 1)
      .toInt();

  String get _label => 'あと${durationLabel(_preview)}';

  void _setIndex(int index) {
    final next =
        himaDurationChoices[index
            .clamp(0, himaDurationChoices.length - 1)
            .toInt()];
    if (next == _preview) return;
    AppHaptics.select();
    setState(() => _preview = next);
  }

  void _setFromPosition(double x, double width) {
    if (width <= 0) return;
    const inset = 22.0;
    final fraction = ((x - inset) / (width - inset * 2)).clamp(0.0, 1.0);
    _setIndex((fraction * (himaDurationChoices.length - 1)).round());
  }

  void _commit() => widget.onCommit(_preview);

  @override
  void didUpdateWidget(InlineDurationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) _preview = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    final previous = index > 0
        ? 'あと${durationLabel(himaDurationChoices[index - 1])}'
        : null;
    final next = index < himaDurationChoices.length - 1
        ? 'あと${durationLabel(himaDurationChoices[index + 1])}'
        : null;

    return PaintThick(
      seed: 6021,
      colors: const [Color(0xFFFFEAF3), Color(0xFFFFD8E9)],
      padding: const EdgeInsets.all(18),
      wobble: 0.045,
      droplets: 10,
      drips: 0,
      arms: 3,
      bristles: false,
      dryEdge: false,
      gloss: 0.8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('ひまの長さ', style: AppTextStyles.sectionTitle),
              ),
              IconButton(
                tooltip: '閉じる',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            _label,
            textAlign: TextAlign.center,
            style: AppTextStyles.heroTitle.copyWith(
              fontSize: 28,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Semantics(
            slider: true,
            label: 'ひまの長さ',
            value: _label,
            increasedValue: next,
            decreasedValue: previous,
            onIncrease: next == null ? null : () => _setIndex(index + 1),
            onDecrease: previous == null ? null : () => _setIndex(index - 1),
            excludeSemantics: true,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _setFromPosition(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
                onTap: _commit,
                onHorizontalDragStart: (details) => _setFromPosition(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
                onHorizontalDragUpdate: (details) => _setFromPosition(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
                onHorizontalDragEnd: (_) => _commit(),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 76),
                  painter: _DurationStrokePainter(
                    progress: index / (himaDurationChoices.length - 1),
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final minutes in himaDurationChoices)
                Text(
                  durationLabel(minutes),
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: minutes == _preview
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Align(
            alignment: Alignment.center,
            child: PaintDab(
              seed: 6031,
              color: AppColors.yellow,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s24,
                vertical: AppSpacing.s8,
              ),
              wobble: 0.07,
              child: TextButton(
                onPressed: _commit,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  textStyle: AppTextStyles.button.copyWith(fontSize: 18),
                ),
                child: const Text('決定'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationStrokePainter extends CustomPainter {
  const _DurationStrokePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 18.0;
    const rightInset = 18.0;
    final right = size.width - rightInset;
    final y = size.height * 0.54;
    final tip = left + (right - left) * progress.clamp(0.0, 1.0);
    final base = Path()
      ..moveTo(left, y + 1)
      ..cubicTo(size.width * 0.36, y - 5, size.width * 0.68, y + 5, right, y);
    final active = Path()
      ..moveTo(left, y + 1)
      ..cubicTo(
        left + (tip - left) * 0.34,
        y - 5,
        left + (tip - left) * 0.72,
        y + 5,
        tip,
        y,
      );

    canvas.drawPath(
      base,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFEBCFD9),
    );
    canvas.drawPath(
      active,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFD52E), Color(0xFFF52D87)],
        ).createShader(Rect.fromLTRB(left, y - 12, right, y + 12)),
    );

    for (var i = 0; i < himaDurationChoices.length; i++) {
      final x = left + (right - left) * i / (himaDurationChoices.length - 1);
      canvas.drawCircle(
        Offset(x, y),
        i / (himaDurationChoices.length - 1) <= progress ? 3.2 : 2.5,
        Paint()..color = AppColors.surface,
      );
    }

    final handle = Offset(tip, y);
    canvas.drawCircle(
      handle.translate(0, 2),
      15,
      Paint()
        ..color = const Color(0x440F0620)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      handle,
      14,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE760), Color(0xFFF72E89)],
        ).createShader(Rect.fromCircle(center: handle, radius: 14)),
    );
    canvas.drawOval(
      Rect.fromCenter(center: handle.translate(-4, -5), width: 5, height: 8),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_DurationStrokePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: AppColors.purple),
          ],
        ),
      ),
    ),
  );
}
