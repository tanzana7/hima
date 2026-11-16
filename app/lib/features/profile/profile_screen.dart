import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../shared/widgets/avatar_view.dart';
import '../../state/app_view_model.dart';
import 'settings_view.dart';

/// プロフィール tab: who you are, then every setting, then logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final me = viewModel.me;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      children: [
        Text('プロフィール', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.s16),
        if (me != null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
              border: Border.all(
                color: AppColors.purpleSoft,
                width: AppSpacing.borderWidth,
              ),
            ),
            child: Row(
              children: [
                AvatarView(
                  name: me.displayName,
                  imageUrl: me.avatarUrl,
                  size: 64,
                  background: AppColors.purpleSoft,
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
                        style: AppTextStyles.caption,
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
