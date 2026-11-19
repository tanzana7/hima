import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Circular avatar with an initials fallback.
///
/// Photos are optional in the contract, so a missing or failing image must
/// still produce a readable, stable circle. The fallback is a pastel gradient
/// picked from the name: a flat grey disc made a friend without an avatar look
/// like a placeholder, while the gradient still keeps the same letter, so the
/// circle stays recognisable.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.background = AppColors.purpleSoft,
    this.foreground = AppColors.ink,
    this.ring,
    this.ringWidth = 3,
  });

  final String name;
  final String? imageUrl;

  static const _assetScheme = 'asset:';
  final double size;
  final Color background;
  final Color foreground;

  /// Draws a ring in this colour around the circle, used by the friend cards
  /// and the hero. The ring is inside [size], so a ringed avatar still occupies
  /// exactly the space the layout reserved for it.
  final Color? ring;
  final double ringWidth;

  /// Pastel partners for the fallback gradient, picked by name so the same
  /// person always gets the same circle.
  static const _accents = [
    AppColors.coral,
    AppColors.purple,
    AppColors.blue,
    AppColors.teal,
    AppColors.orange,
  ];

  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '？';
    return String.fromCharCode(trimmed.runes.first);
  }

  Color get _accent {
    if (name.isEmpty) return AppColors.purple;
    return _accents[name.runes.fold(0, (sum, rune) => sum + rune) %
        _accents.length];
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final inner = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            background,
            Color.lerp(background, _accent, 0.45) ?? background,
          ],
        ),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? _initials()
          // `asset:` marks a bundled image (the mock users' avatars); anything
          // else is a remote URL such as Discord's CDN. Both fall back to the
          // initials, so a missing file never leaves an empty circle.
          : url.startsWith(_assetScheme)
          ? Image.asset(
              url.substring(_assetScheme.length),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initials(),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initials(),
            ),
    );
    final ringColor = ring;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: ringColor == null ? null : EdgeInsets.all(ringWidth),
        decoration: ringColor == null
            ? null
            : BoxDecoration(color: ringColor, shape: BoxShape.circle),
        child: inner,
      ),
    );
  }

  Widget _initials() => Center(
    child: Text(
      _initial,
      style: TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: size * 0.4,
        fontWeight: FontWeight.w800,
        color: foreground,
      ),
    ),
  );
}
