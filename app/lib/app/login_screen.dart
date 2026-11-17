import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_spacing.dart';
import '../app/theme/app_text_styles.dart';
import '../data/api_client.dart';
import '../data/app_config.dart';
import '../data/discord_oauth.dart';
import '../shared/widgets/hima_logo.dart';
import '../shared/widgets/paint/paint.dart';
import '../shared/widgets/paint_button.dart';
import '../state/app_view_model.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.config});

  final AppConfig config;

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _login(BuildContext context, AppViewModel viewModel) async {
    if (config.useMockApi) {
      try {
        await viewModel.loginAsDemo();
      } catch (_) {
        if (context.mounted) {
          _showMessage(context, 'ログインできなかった。もう一度試してね');
        }
      }
      return;
    }
    if (config.discordClientId.isEmpty) {
      _showMessage(context, 'Discordの設定が足りないよ');
      return;
    }
    try {
      final request = await DiscordOAuth(
        clientId: config.discordClientId,
      ).authorize();
      if (!context.mounted) return;
      await viewModel.completeDiscordLogin(request);
    } on DiscordLoginCancelled {
      // Closing the Discord page is not a failure, so nothing is shown.
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(
        context,
        error is ApiException
            ? error.message
            : 'ログインできなかった。もう一度試してね',
      );
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
                  // The logo and the headline sit on two brush passes: a lemon
                  // stroke that went down first, tilted, and the coral one that
                  // landed across it. A stroke is what the rest of the app is
                  // painted with; the splash that used to be here read as a
                  // wide rectangle with drips hanging off it.
                  Stack(
                    // The column above stretches the stack to the full width,
                    // so the stroke is centred explicitly: the default
                    // top-start would park it against the left edge whenever it
                    // ends up narrower than the stack.
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Transform.rotate(
                          // A couple of degrees is enough to read as a second
                          // pass of the brush instead of a second layer.
                          angle: -0.035,
                          child: BrushSwipe(
                            seed: 8123,
                            colors: const [
                              AppColors.lemonSoft,
                              AppColors.skySoft,
                            ],
                            padding: const EdgeInsets.all(AppSpacing.s24),
                            droplets: 12,
                          ),
                        ),
                      ),
                      // The width is forced: a Stack sizes to its largest
                      // non-positioned child, and without this the stroke would
                      // shrink to the logo's intrinsic width while the tilted
                      // pass behind it kept the full width.
                      SizedBox(
                        width: double.infinity,
                        child: BrushSwipe(
                          seed: 4211,
                          colors: const [
                            AppColors.lemonSoft,
                            AppColors.coralLight,
                          ],
                          padding: const EdgeInsets.all(AppSpacing.s24),
                          droplets: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // The wordmark keeps its fixed size: it is a mark,
                              // not body text, and the headline below carries
                              // the message at every text scale.
                              Center(
                                child: MediaQuery.withNoTextScaling(
                                  child: const HimaLogo(fontSize: 56),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s16),
                              Text(
                                'いま、ひま？',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.heroTitle,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Droplets thrown clear of the paint, kept off the text.
                      const Positioned(
                        top: 0,
                        left: 0,
                        child: SplatterDots(
                          seed: 91,
                          size: Size(26, 22),
                          color: AppColors.coral,
                          count: 6,
                        ),
                      ),
                      const Positioned(
                        bottom: 4,
                        right: 0,
                        child: SplatterDots(
                          seed: 93,
                          size: Size(24, 20),
                          color: AppColors.purple,
                          count: 5,
                        ),
                      ),
                    ],
                  ),
                  // The splatter stays inside the band, but the lemon pass is
                  // tilted a couple of degrees, so its corner dips below the
                  // box. The gap keeps that corner clear of
                  // 「ひまなら友達に知らせよう」.
                  const SizedBox(height: AppSpacing.s32),
                  Text(
                    'ひまなら友達に知らせよう',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.s32),
                  // A big lemon dab with ink text, the same primary as the home
                  // screen's 「ひまを宣言」.
                  PaintButton(
                    seed: 3301,
                    label: 'Discordでログイン',
                    color: AppColors.yellow,
                    foreground: AppColors.ink,
                    minHeight: 56,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s24,
                      vertical: AppSpacing.s16,
                    ),
                    textStyle: AppTextStyles.button.copyWith(fontSize: 17),
                    onPressed: viewModel.isBusy
                        ? null
                        : () => _login(context, viewModel),
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
