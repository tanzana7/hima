import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small horizontal shake for a control whose action failed.
///
/// Callers keep the previous state and shake the control that failed instead of
/// showing a fake success.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.child});

  final Widget child;

  @override
  State<Shake> createState() => ShakeState();
}

class ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
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
      final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 6) * 9 * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}
