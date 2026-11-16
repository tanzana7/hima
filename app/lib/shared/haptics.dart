import 'package:flutter/services.dart';

/// Haptic rhythms built from Flutter's built-in [HapticFeedback].
///
/// Short delays between calls create the "double tap" and celebratory rhythms;
/// no vibration package is used. Haptics stay on even when animations are
/// reduced, because they are feedback rather than decoration.
abstract final class AppHaptics {
  static Future<void> select() => HapticFeedback.selectionClick();

  static Future<void> openMenu() => HapticFeedback.mediumImpact();

  static Future<void> declare() => HapticFeedback.heavyImpact();

  static Future<void> end() => HapticFeedback.lightImpact();

  static Future<void> send() => HapticFeedback.lightImpact();

  static Future<void> cancel() => HapticFeedback.lightImpact();

  /// Match card arrival: two quick medium taps.
  static Future<void> match() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.mediumImpact();
  }

  /// 「いいよ！」 arrived: light, light, heavy.
  static Future<void> celebrate() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.heavyImpact();
  }

  static Future<void> error() => HapticFeedback.vibrate();
}
