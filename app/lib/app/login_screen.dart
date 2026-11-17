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
                  // The logo and the headline sit on layered paint: a lavender
                  // splash underneath and a lemon→coral one on top. Both keep
                  // their content inside the safe rect, so the ink text is
                  // always on colour and never on bare paper.
                  Stack(
                    // The column above stretches the stack to the full width,
                    // so the splash is centred explicitly: the default
                    // top-start would park it against the left edge whenever it
                    // ends up narrower than the stack.
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: PaintSplat(
                          seed: 8123,
                          colors: const [
                            AppColors.purpleSoft,
                            AppColors.skySoft,
                          ],
                          padding: const EdgeInsets.all(AppSpacing.s24),
                          corner: 56,
                          wobble: 0.09,
                          droplets: 8,
                          drips: 1,
                        ),
                      ),
                      PaintSplat(
                        seed: 4211,
                        colors: const [
                          AppColors.lemonSoft,
                          AppColors.coralLight,
                        ],
                        padding: const EdgeInsets.all(AppSpacing.s24),
                        corner: 56,
                        // A wide box with a small wobble reads as a rounded
                        // rectangle, so the login splash leans on a stronger
                        // one: it is the only shape on the screen and has to
                        // carry the wet-paint look by itself.
                        wobble: 0.085,
                        droplets: 10,
                        drips: 2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // The wordmark keeps its fixed size: it is a mark,
                            // not body text, and the headline below carries the
                            // message at every text scale.
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
                  // The splash throws arms and drips up to `paintMaxBleed` past
                  // its box, and the left drip used to run into the subtitle.
                  // Reserving exactly that band is the only gap that holds for
                  // every seed and text scale: a fixed 24dp put the drip
                  // through 「ひまなら友達に知らせよう」.
                  const SizedBox(height: paintMaxBleed + AppSpacing.s8),
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
