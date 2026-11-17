import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import 'paint/paint.dart';

/// A button whose background is a paint dab instead of a stadium or an
/// outline, so the friend, knock and settings screens speak the same control
/// language as the home screen's 「ひまを宣言」.
///
/// The fill and the label colour are passed in rather than derived: a primary
/// action takes the purple dab with white text, a secondary one a soft tint
/// with ink text, and the caller is the only one that knows which it is.
///
/// The dab has no fixed height. A fixed box clipped the label at 200% text
/// scale, so it keeps a minimum tap target and grows with its text instead.
class PaintButton extends StatelessWidget {
  const PaintButton({
    super.key,
    required this.seed,
    required this.label,
    required this.color,
    required this.foreground,
    required this.onPressed,
    this.icon,
    this.minHeight = AppSpacing.minTapTarget,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.s16,
      vertical: AppSpacing.s12,
    ),
    this.textStyle,
    this.semanticLabel,
  });

  /// Keeps one button's silhouette stable across rebuilds and scrolling.
  final int seed;

  final String label;
  final Color color;
  final Color foreground;

  /// Null disables the button: the dab turns to [AppColors.mutedSoft] and stops
  /// accepting taps, which is the state the knock sheet's send button uses
  /// while a knock is in flight.
  final VoidCallback? onPressed;

  final IconData? icon;
  final double minHeight;
  final EdgeInsets padding;
  final TextStyle? textStyle;

  /// Spoken name when the visible label is too terse to stand alone.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // A disabled dab keeps an ink label on the muted tint instead of fading the
    // text: `muted` on `mutedSoft` is 4.0:1, and a disabled control still has
    // to be readable.
    final fill = enabled ? color : AppColors.mutedSoft;
    final ink = enabled ? foreground : AppColors.ink;
    final style = (textStyle ?? AppTextStyles.button.copyWith(fontSize: 16))
        .copyWith(color: ink);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      // The child's semantics are excluded, so the wrapper has to carry the
      // action itself or the button cannot be activated by a screen reader.
      onTap: onPressed,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Center(
            child: PaintDab(
              seed: seed,
              color: fill,
              padding: padding,
              wobble: 0.035,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: ink),
                    const SizedBox(width: AppSpacing.s8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: style,
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
