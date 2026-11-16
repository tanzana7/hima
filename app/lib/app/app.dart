import 'package:flutter/material.dart';

import 'app_root.dart';
import 'theme/app_theme.dart';

class HimaApp extends StatelessWidget {
  const HimaApp({super.key, required this.mockMode});

  final bool mockMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'hima.',
    debugShowCheckedModeBanner: false,
    theme: buildHimaTheme(),
    home: AppRoot(mockMode: mockMode),
  );
}
