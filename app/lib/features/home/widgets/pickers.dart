import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/activity_style.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/models/models.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/paint/paint.dart';

/// 30分 / 1時間 / 2時間 picker used by the tappable remaining-time pill.
Future<int?> showDurationPicker(BuildContext context, {required int current}) =>
    showModalBottomSheet<int>(
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
            const Text('ひまの長さ', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.s12),
            for (final minutes in himaDurationChoices)
              _ChoiceTile(
                label: durationLabel(minutes),
                selected: minutes == current,
                onTap: () => Navigator.of(sheetContext).pop(minutes),
              ),
          ],
        ),
      ),
    );

/// Small mood picker opened from the hero badge while declared.
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

/// The activity picked in [showActivityPicker].
///
/// A plain `Activity?` cannot express the difference between "dismissed" and
/// "cleared", and clearing the choice has to reach the API.
class ActivityChoice {
  const ActivityChoice(this.activity);

  final Activity? activity;
}

/// The point the last tap landed on, in global coordinates.
///
/// [showActivityPicker] keeps its public signature — the hero and the demo panel
/// both call it — so its callers cannot hand it the position of the control they
/// pressed. The app records the last pointer-down instead ([ActivityPickerAnchorListener])
/// and the picker grows its wash out of that point.
abstract final class ActivityPickerAnchor {
  static Offset? _point;

  static Offset? get point => _point;

  static void record(Offset point) => _point = point;
}

/// Records where each tap lands, for [ActivityPickerAnchor].
///
/// It only listens: `Listener` never competes in the gesture arena, so wrapping
/// the navigator with it changes no gesture in the app.
class ActivityPickerAnchorListener extends StatelessWidget {
  const ActivityPickerAnchorListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    // `deferToChild` (the default) records only real taps, not the empty paper
    // around a control.
    behavior: HitTestBehavior.deferToChild,
    onPointerDown: (event) => ActivityPickerAnchor.record(event.position),
    child: child,
  );
}

/// 「なにする？」 picker opened from the declared hero's meta row.
///
/// The declared hero hides the chip row to stay calm, so the same single
/// optional choice is offered here instead. Dismissing the sheet returns null;
/// choosing 「なし」 returns a choice with a null activity. The look is the paint
/// kit's: the sheet opens as a splash of paint whose drops settle into the five
/// activity blobs (see [_ActivityPaintSheet]).
Future<ActivityChoice?> showActivityPicker(
  BuildContext context, {
  required Activity? current,
}) => showModalBottomSheet<ActivityChoice>(
  context: context,
  useSafeArea: true,
  // Scrollable so 200% text can push the blob cluster past the usual sheet
  // height instead of clipping it.
  isScrollControlled: true,
  // The sheet is paper with paint thrown on it, so it stays the theme's own
  // surface; only the backdrop is darkened, in ink like every other scrim.
  barrierColor: AppColors.ink.withValues(alpha: 0.32),
  builder: (sheetContext) => _ActivityPaintSheet(current: current),
);

/// The painted activity picker: a soft wash of paint with the five activities
/// thrown onto it.
class _ActivityPaintSheet extends StatefulWidget {
  const _ActivityPaintSheet({required this.current});

  final Activity? current;

  @override
  State<_ActivityPaintSheet> createState() => _ActivityPaintSheetState();
}

class _ActivityPaintSheetState extends State<_ActivityPaintSheet>
    with SingleTickerProviderStateMixin {
  /// The splash and the blobs, staggered: the drops go out first and the blobs
  /// land after them, so the sheet looks thrown onto the paper rather than
  /// switched on.
  static const _popDuration = Duration(milliseconds: 620);

  /// The paper the blobs keep clear around themselves, inside the splash.
  static const _splashPadding = EdgeInsets.all(18);

  late final AnimationController _pop;

  /// Where the wash grows from, in the splash's own alignment.
  ///
  /// The tapping control sits above the sheet, so the point is clamped into the
  /// splash box: the burst comes out of the sheet's edge directly under the
  /// control that was pressed.
  Alignment _origin = Alignment.topCenter;

  final GlobalKey _splashKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: _popDuration);
    // The origin needs the splash's box, which only exists after the first
    // layout, so the splash starts once that frame has run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resolveOrigin();
      if (MediaQuery.disableAnimationsOf(context)) {
        _pop.value = 1;
      } else {
        _pop.forward();
      }
    });
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  /// Turns the recorded tap into an alignment inside the splash.
  void _resolveOrigin() {
    final point = ActivityPickerAnchor.point;
    final box = _splashKey.currentContext?.findRenderObject();
    if (point == null || box is! RenderBox || box.size.isEmpty) return;
    final local = box.globalToLocal(point);
    setState(() {
      _origin = Alignment(
        (local.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
      );
    });
  }

  void _choose(Activity activity) {
    AppHaptics.select();
    Navigator.of(context).pop(ActivityChoice(activity));
  }

  void _clear() {
    AppHaptics.select();
    Navigator.of(context).pop(const ActivityChoice(null));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          0,
          AppSpacing.s16,
          AppSpacing.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('なにする？', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.s8),
            _splash(reduceMotion),
            if (widget.current != null) ...[
              const SizedBox(height: AppSpacing.s8),
              // Only offered when something is chosen: it is the way back to
              // 「なし」, not a sixth activity.
              Align(
                alignment: Alignment.centerRight,
                child: _ClearChoice(onTap: _clear),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _splash(bool reduceMotion) {
    final washLight = paintTone(AppColors.coralLight, 0.74);
    final washDeep = paintTone(AppColors.coralLight, 0.64);
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, _) {
        final t = reduceMotion ? 1.0 : _pop.value;
        return Stack(
          key: _splashKey,
          clipBehavior: Clip.none,
          children: [
            // The wash bursts out of the control that opened the picker
            // ([ActivityPickerAnchor]): the drops it throws are the paint the
            // activity blobs land on. The control sits above the sheet, so the
            // point is clamped to the splash's edge under it.
            Positioned.fill(
              child: PaintSplat(
                seed: paintSeedOf('activity-wash'),
                colors: [washLight, washDeep],
                padding: _splashPadding,
                corner: 999,
                wobble: 0.055,
                droplets: 14,
                drips: 0,
                arms: 4,
                armLength: 0.05,
                minScale: 0.4,
                origin: _origin,
                progress: t,
              ),
            ),
            Padding(
              padding: _splashPadding,
              child: Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                alignment: WrapAlignment.center,
                children: [
                  for (var index = 0; index < Activity.values.length; index++)
                    _ActivityBlob(
                      key: ValueKey(Activity.values[index]),
                      activity: Activity.values[index],
                      selected: Activity.values[index] == widget.current,
                      pop: _blobPop(index),
                      onTap: _choose,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Each blob is thrown a little later than the one before it, from its own
  /// direction, and lands with an elastic overshoot.
  Animation<double> _blobPop(int index) {
    final start = 0.23 + 0.06 * index;
    return CurvedAnimation(
      parent: _pop,
      curve: Interval(
        start.clamp(0.0, 0.7),
        (start + 0.5).clamp(0.3, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// The same hue as one of the activity's pastels, mixed to a paint you can see.
///
/// The activity tints are pale enough that on the pink wash a blob of them reads
/// as a translucent smudge. Deepening the tint's own hue keeps each activity's
/// colour — and, unlike mixing towards [ActivityStyle.accent], it does not turn
/// 「なんでもOK」 grey, because that activity's accent is the ink used for its
/// icon rather than a colour of its own.
Color _paintFill(Color tint, {required bool selected}) {
  final hsl = HSLColor.fromColor(tint);
  return hsl
      .withLightness((hsl.lightness - (selected ? 0.2 : 0.11)).clamp(0.0, 1.0))
      .toColor();
}

/// One activity as a glossy blob of paint.
class _ActivityBlob extends StatefulWidget {
  const _ActivityBlob({
    super.key,
    required this.activity,
    required this.selected,
    required this.pop,
    required this.onTap,
  });

  final Activity activity;
  final bool selected;
  final Animation<double> pop;
  final ValueChanged<Activity> onTap;

  @override
  State<_ActivityBlob> createState() => _ActivityBlobState();
}

class _ActivityBlobState extends State<_ActivityBlob> {
  bool _pressed = false;

  /// The direction this blob is thrown in from, seeded so it is the same every
  /// time the picker opens.
  Offset get _throwDirection {
    final angle = (paintSeedOf(widget.activity.name) % 360) * math.pi / 180;
    return Offset(math.cos(angle), math.sin(angle));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final style = ActivityStyle.of(widget.activity);
    // The selected blob is pushed towards its accent so the choice reads as more
    // paint rather than as an outline. Both stops are pushed: the pastel tints
    // alone are so pale that on the pink wash they read as translucent rather
    // than as blobs of paint.
    final fill = _paintFill(style.background, selected: widget.selected);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.activity.label,
      // `excludeSemantics` drops the gesture detector below, action included, so
      // the node carries the tap itself or the choice is unreachable for screen
      // readers.
      onTap: () => widget.onTap(widget.activity),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => widget.onTap(widget.activity),
        child: AnimatedBuilder(
          animation: widget.pop,
          builder: (context, child) {
            final t = reduceMotion ? 1.0 : widget.pop.value;
            // Elastic on the way in: the blob overshoots its size and settles,
            // which is what makes a group of them look thrown rather than laid
            // out.
            final land = reduceMotion
                ? 1.0
                : Curves.elasticOut.transform(t.clamp(0.0, 1.0));
            return Transform.translate(
              offset: _throwDirection * (24 * (1 - t)),
              child: Transform.scale(scale: 0.35 + 0.65 * land, child: child),
            );
          },
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            child: ConstrainedBox(
              // 48dp is the minimum tap target; the dab's own padding keeps the
              // label off the paint's edge as the text grows.
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTapTarget,
                minHeight: AppSpacing.minTapTarget,
              ),
              child: PaintThick(
                seed: paintSeedOf('activity-${widget.activity.name}'),
                colors: [paintTone(fill, 0.10), fill],
                padding: EdgeInsets.symmetric(
                  horizontal: widget.selected ? 18 : 16,
                  vertical: widget.selected ? 16 : 13,
                ),
                wobble: 0.10,
                droplets: widget.selected ? 2 : 1,
                drips: 0,
                arms: 0,
                gloss: widget.selected ? 1 : 0.75,
                // A dab this small has no edge band to break up: the dry brush
                // would eat most of its paint instead of tearing the outline.
                dryEdge: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon, size: 16, color: style.accent),
                    const SizedBox(width: AppSpacing.s8),
                    Flexible(
                      child: Text(
                        widget.activity.label,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 14,
                          fontWeight: widget.selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (widget.selected) ...[
                      const SizedBox(width: AppSpacing.s4),
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppColors.ink,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The way back to 「なし」, for a declaration that already has an activity.
class _ClearChoice extends StatelessWidget {
  const _ClearChoice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'やりたいことを選ばない',
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Center(
          widthFactor: 1,
          child: PaintDab(
            seed: 81,
            color: AppColors.mutedSoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            wobble: 0.08,
            child: Text(
              'なし',
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
    // `excludeSemantics` drops the InkWell below, including its tap action, so
    // the node has to carry the action itself or the choice is unreachable for
    // screen reader users.
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.s8),
        decoration: BoxDecoration(
          color: selected ? AppColors.purpleSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? AppColors.purple : AppColors.purpleSoft,
            width: AppSpacing.borderWidth,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                style: AppTextStyles.body.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.purple,
              ),
          ],
        ),
      ),
    ),
  );
}
