import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/app_config.dart';
import 'app_root.dart';
import 'theme/app_theme.dart';

class HimaApp extends StatelessWidget {
  const HimaApp({super.key, required this.config});

  final AppConfig config;

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
  Widget build(BuildContext context) => MaterialApp(
    title: 'hima.',
    debugShowCheckedModeBanner: false,
    theme: buildHimaTheme(),
    locale: _locale,
    supportedLocales: const [_locale],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: AppRoot(config: config),
  );
}
