import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../state/session_owner.dart';
import 'demo_panel.dart';

/// Paints the demo panel's entry point over the whole app.
///
/// It sits above the navigator on purpose: the catalog has to be reachable from
/// every route, including the pages it pushes itself, and a Scaffold-level
/// button would be left behind by the next push.
class DemoOverlay extends StatelessWidget {
  const DemoOverlay({super.key, required this.demo, required this.child});

  final DemoSession demo;
  final Widget child;

  /// How far the button is lifted off the bottom of the screen.
  ///
  /// The shell floats its navigation over the content (`Scaffold.extendBody`),
  /// so the nav's top edge moves up as the text scale grows: the fade plus one
  /// tab row, whose label wraps to two lines at 200%. This clears that band, and
  /// it also keeps the button below the hero, where 「ひまを宣言」 sits, on every
  /// phone the app is laid out for.
  static const _bottomInset = 208.0;

  /// The corner that leaves 撮影モード, over the logo.
  static const _captureExitSize = 72.0;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: demo.captureMode,
    // Nothing developer-looking may be on screen while the owner records, so
    // the entry point is not built at all and the way out takes its place.
    builder: (context, captureMode, _) => Stack(
      children: [
        Positioned.fill(child: child),
        if (captureMode)
          Positioned(
            left: 0,
            top: MediaQuery.paddingOf(context).top,
            child: _CaptureModeExit(
              size: _captureExitSize,
              onExit: () => demo.captureMode.value = false,
            ),
          )
        else
          Positioned(
            right: AppSpacing.s12,
            bottom: _bottomInset + MediaQuery.viewPaddingOf(context).bottom,
            child: ValueListenableBuilder<bool>(
              valueListenable: demo.panelVisible,
              builder: (context, panelVisible, _) => panelVisible
                  ? const SizedBox.shrink()
                  : _DemoPanelButton(onTap: () => openDemoPanel(demo)),
            ),
          ),
      ],
    ),
  );
}

/// The way out of 撮影モード: a long press on the top-left corner.
///
/// It has to be invisible, because it is on screen throughout the recording. It
/// is translucent and claims only a long press, so every tap and scroll keeps
/// reaching the screen underneath; the corner is where the logo is, which is not
/// tappable, so the gesture cannot be mistaken for a control of the app.
class _CaptureModeExit extends StatelessWidget {
  const _CaptureModeExit({required this.size, required this.onExit});

  final double size;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '撮影モードを終える',
    // A screen reader cannot perform a long press reliably, so the node offers
    // the same exit as a plain activation too.
    onTap: onExit,
    onLongPress: onExit,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: onExit,
      child: SizedBox.square(dimension: size),
    ),
  );
}

/// The floating entry point. A paint-coloured circle, so it reads as part of the
/// app's own controls rather than as a debug badge.
class _DemoPanelButton extends StatelessWidget {
  const _DemoPanelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'デモパネルを開く',
    // The child's semantics are excluded, action included, so the node carries
    // the tap itself or the button cannot be activated by a screen reader.
    onTap: onTap,
    excludeSemantics: true,
    child: Material(
      color: AppColors.purple,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          child: Icon(
            Icons.science_rounded,
            size: 22,
            color: AppColors.surface,
          ),
        ),
      ),
    ),
  );
}
