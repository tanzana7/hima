import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Circular avatar with an initials fallback.
///
/// Photos are optional in the contract, so a missing or failing image must
/// still produce a readable, stable circle.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.background = AppColors.purpleSoft,
    this.foreground = AppColors.ink,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color background;
  final Color foreground;

  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '？';
    return String.fromCharCode(trimmed.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: url == null
            ? _initials()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initials(),
              ),
      ),
    );
  }

  Widget _initials() => Center(
    child: Text(
      _initial,
      style: TextStyle(
        fontSize: size * 0.4,
        fontWeight: FontWeight.w800,
        color: foreground,
      ),
    ),
  );
}
