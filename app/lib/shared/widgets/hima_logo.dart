import 'package:flutter/material.dart';

import '../../app/theme/app_text_styles.dart';
import 'decorations.dart';

/// The `hima.` wordmark: rounded type plus a lime underline swoosh.
///
/// It is plain text on purpose so it scales with the system text size and stays
/// readable to screen readers; no image asset is used for the name.
class HimaLogo extends StatelessWidget {
  const HimaLogo({super.key, this.fontSize = 40});

  final double fontSize;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: 'hima.',
    child: ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: fontSize * 0.14),
            child: Text(
              'hima.',
              style: AppTextStyles.logo.copyWith(fontSize: fontSize),
            ),
          ),
          Positioned(
            left: fontSize * 0.04,
            right: fontSize * 0.5,
            bottom: 0,
            height: fontSize * 0.22,
            child: const CustomPaint(painter: SwooshPainter()),
          ),
        ],
      ),
    ),
  );
}
