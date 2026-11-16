import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small horizontal shake for a control whose action failed.
///
/// Callers keep the previous state and shake the control that failed instead of
/// showing a fake success. The movement is decoration, so reduced motion turns
/// it off; the error haptic still fires.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.child});

  final Widget child;

  @override
  State<Shake> createState() => ShakeState();
}

class ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 300);

  /// Peak sideways travel in logical pixels.
  static const _amplitude = 6.0;

  /// Sideways swings before the control settles back where it started.
  static const _swings = 3.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
  }

  void shake() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = _controller.value;
      final dx = math.sin(t * math.pi * 2 * _swings) * _amplitude * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}
