import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../shared/widgets/app_bottom_navigation.dart';
import '../../shared/widgets/avatar_view.dart';
import '../../shared/widgets/paint/paint.dart';
import '../../state/app_view_model.dart';
import 'settings_view.dart';

/// Captions that sit directly on a [PaintWash]. [AppColors.muted] measures
/// 4.2:1 on the pastel wash, so text on paint takes this darker tone instead
/// (5.4:1).
const _washMuted = Color(0xFF635B6F);

/// プロフィール tab: who you are, then every setting, then logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final me = viewModel.me;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppBottomNavigation.listBottomInset(context),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('プロフィール', style: AppTextStyles.sectionTitle),
                  BrushStroke(
                    seed: 71,
                    size: const Size(120, 9),
                    color: AppColors.purple.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
            const SplatterDots(
              seed: 73,
              size: Size(22, 18),
              color: AppColors.coral,
              count: 5,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        if (me != null)
          // A wash instead of a bordered white card: the paint is the card's
          // edge, and the seed comes from my id so the silhouette is stable.
          PaintWash(
            seed: paintSeedOf('profile-${me.id}'),
            color: AppColors.purpleSoft,
            padding: const EdgeInsets.all(AppSpacing.s16),
            corner: AppSpacing.radiusCard,
            child: Row(
              children: [
                AvatarView(
                  name: me.displayName,
                  imageUrl: me.avatarUrl,
                  size: 64,
                  // The card is already the same lavender, so the avatar takes
                  // a white ring to stay a separate circle on the paint.
                  background: AppColors.surface.withValues(alpha: 0.9),
                  ring: AppColors.surface,
                ),
                const SizedBox(width: AppSpacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        me.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.friendName.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        '${viewModel.guilds.length}つのサーバーで共有中',
                        style: AppTextStyles.caption.copyWith(
                          color: _washMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s24),
        const SettingsView(showLogout: true),
      ],
    );
  }
}
