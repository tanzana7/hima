import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';
import '../../shared/widgets/brush_title.dart';
import 'settings_view.dart';

/// Settings reached from the header gear. It shows the same content as the
/// プロフィール tab without the logout action, which belongs to the profile.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      // The same brush-stroke underline the tab titles carry. The toolbar grows
      // with the text scale so the stroke is never clipped.
      toolbarHeight: BrushTitle.toolbarHeight(context),
      title: const BrushTitle(title: '設定', seed: 89),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      children: const [SettingsView(showLogout: false)],
    ),
  );
}
