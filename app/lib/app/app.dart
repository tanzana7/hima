import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../data/app_config.dart';
import '../features/demo/demo_overlay.dart';
import '../state/app_view_model.dart';
import '../state/hima_suggest_controller.dart';
import '../state/session_owner.dart';
import 'app_root.dart';
import 'theme/app_theme.dart';

class HimaApp extends StatelessWidget {
  const HimaApp({super.key, required this.config, required this.sessions});

  final AppConfig config;

  /// Which session is on screen, and the demo once it is entered.
  final SessionOwner sessions;

  /// The app is Japanese-only, so the locale is fixed instead of following
  /// the device. Without it, text is laid out as en-US: Material's own
  /// strings (tooltips, the back button's screen-reader label) are English,
  /// and any character the bundled font lacks falls back by the en-US
  /// order, which prefers Chinese glyph shapes for kanji.
  ///
  /// The delegates are what make `ja` usable: without them a `ja` locale
  /// would leave MaterialLocalizations missing.
  ///
  /// The locale alone did not fix kanji turning Mincho on some Android
  /// phones; the bundled font in AppTextStyles does.
  static const _locale = Locale('ja', 'JP');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sessions,
    builder: (context, _) {
      final session = sessions.active;
      final demo = sessions.demo;
      return MultiProvider(
        // Keyed by the session, and the key has to cover the whole subtree: a
        // swap rebuilds every route, so the Navigator drops whatever page, sheet
        // or dialog belonged to the session being left, and `MainShell` re-reads
        // its own session fields from the new providers.
        key: ValueKey(session),
        providers: [
          ChangeNotifierProvider<AppViewModel>.value(value: session.viewModel),
          ChangeNotifierProvider<HimaSuggestController>.value(
            value: session.suggest,
          ),
          // Null in the real session, so nothing of the demo is reachable there
          // and the demo widgets can ask for it without a second look-up type.
          Provider<DemoSession?>.value(value: demo),
          // `.value`, so the owner outlives the providers handed to it: it is
          // created once in `main`, not per session.
          ChangeNotifierProvider<SessionOwner>.value(value: sessions),
        ],
        child: MaterialApp(
          key: ValueKey(session),
          title: 'hima.',
          debugShowCheckedModeBanner: false,
          theme: buildHimaTheme(),
          locale: _locale,
          supportedLocales: const [_locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          navigatorKey: demo?.navigatorKey,
          // The panel's entry point has to outlive every route, so it is painted
          // above the navigator rather than inside a Scaffold.
          builder: (context, child) {
            final navigator = child ?? const SizedBox.shrink();
            if (demo == null) return navigator;
            return DemoOverlay(demo: demo, child: navigator);
          },
          home: AppRoot(config: config),
        ),
      );
    },
  );
}
