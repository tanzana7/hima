import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_view_model.dart';
import 'main_navigation.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key, required this.mockMode});

  final bool mockMode;

  @override
  Widget build(BuildContext context) => Consumer<AppViewModel>(
    builder: (context, viewModel, _) => viewModel.isAuthenticated
        ? const MainNavigation()
        : LoginScreen(mockMode: mockMode),
  );
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.mockMode});

  final bool mockMode;

  Future<void> _login(BuildContext context, AppViewModel viewModel) async {
    if (!mockMode) {
      // TODO: Start Discord OAuth2 PKCE in a browser and handle the custom-scheme redirect.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Discordログインは準備中です')));
      return;
    }
    try {
      await viewModel.loginAsDemo();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインできませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Consumer<AppViewModel>(
              builder: (context, viewModel, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.waving_hand_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'あつまろ',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '友だちの「今ヒマ！」が見つかる',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: viewModel.isBusy
                        ? null
                        : () => _login(context, viewModel),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Discordでログイン'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
