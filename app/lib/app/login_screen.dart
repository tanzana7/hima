import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_spacing.dart';
import '../app/theme/app_text_styles.dart';
import '../shared/widgets/hima_logo.dart';
import '../state/app_view_model.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.mockMode});

  final bool mockMode;

  Future<void> _login(BuildContext context, AppViewModel viewModel) async {
    if (!mockMode) {
      // TODO: Start Discord OAuth2 PKCE in a browser and handle the
      // custom-scheme redirect.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Discordログインは準備中です')));
      return;
    }
    try {
      await viewModel.loginAsDemo();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ログインできなかった。もう一度試してね')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: Consumer<AppViewModel>(
              builder: (context, viewModel, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: MediaQuery.withNoTextScaling(
                      child: const HimaLogo(fontSize: 56),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  Text(
                    'いま、ひま？',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heroTitle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'ひまなら友達に知らせよう',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.s32),
                  FilledButton(
                    onPressed: viewModel.isBusy
                        ? null
                        : () => _login(context, viewModel),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.yellow,
                      foregroundColor: AppColors.ink,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: const Text('Discordでログイン'),
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
