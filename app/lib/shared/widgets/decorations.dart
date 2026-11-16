import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The lime underline under the `hima.` wordmark.
class SwooshPainter extends CustomPainter {
  const SwooshPainter({this.color = AppColors.lime});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.6
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * 0.8)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.05,
        size.width,
        size.height * 0.55,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(SwooshPainter oldDelegate) => oldDelegate.color != color;
}

/// A four point sparkle used next to section titles.
class StarPainter extends CustomPainter {
  const StarPainter({this.color = AppColors.yellow});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? size.width / 2 : size.width / 6;
      final angle = -math.pi / 2 + i * math.pi / 4;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(StarPainter oldDelegate) => oldDelegate.color != color;
}

/// A static sparkle accent with a fixed size.
class StarAccent extends StatelessWidget {
  const StarAccent({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: StarPainter(color: color ?? AppColors.yellow)),
    ),
  );
}
