import 'package:flutter/material.dart';

import '../data/app_config.dart';
import 'app_root.dart';
import 'theme/app_theme.dart';

class HimaApp extends StatelessWidget {
  const HimaApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'hima.',
    debugShowCheckedModeBanner: false,
    theme: buildHimaTheme(),
    home: AppRoot(config: config),
  );
}
