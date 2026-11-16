import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';
import 'settings_view.dart';

/// Settings reached from the header gear. It shows the same content as the
/// プロフィール tab without the logout action, which belongs to the profile.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('設定')),
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
