import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_view_model.dart';
import 'login_screen.dart';
import 'main_shell.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key, required this.mockMode});

  final bool mockMode;

  @override
  Widget build(BuildContext context) => Consumer<AppViewModel>(
    builder: (context, viewModel, _) => viewModel.isAuthenticated
        ? const MainShell()
        : LoginScreen(mockMode: mockMode),
  );
}
