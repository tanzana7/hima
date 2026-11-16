import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/avatar_view.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/knock_pill.dart';
import '../../state/app_view_model.dart';
import '../knocks/widgets/knock_sheet.dart';

/// 友達 tab: everyone in the shared servers, grouped by server.
///
/// Free people come first inside each server and only they get さそう; people
/// who are not free are listed below without guessing what they are doing.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final servers = viewModel.friendServers;
    final query = _query.trim().toLowerCase();
    final filtered = [
      for (final server in servers)
        FriendServer(
          guild: server.guild,
          members: [
            for (final member in server.members)
              if (query.isEmpty ||
                  member.user.displayName.toLowerCase().contains(query))
                member,
          ],
        ),
    ].where((server) => server.members.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      children: [
        Text('友達', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.s12),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: '名前でさがす',
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.muted,
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'クリア',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.s24),
        if (servers.isEmpty)
          if (viewModel.isRefreshingLive)
            const LoadingState()
          else if (viewModel.hasLiveError)
            EmptyState(
              message: '友達を読み込めなかったよ',
              icon: Icons.cloud_off_rounded,
              action: TextButton(
                onPressed: () => unawaited(viewModel.refreshLiveData()),
                child: const Text('もう一度'),
              ),
            )
          else
            const EmptyState(
              message: 'まだ友達がいないよ',
              icon: Icons.people_outline_rounded,
            )
        else if (filtered.isEmpty)
          const EmptyState(
            message: '見つからなかったよ',
            icon: Icons.search_off_rounded,
          )
        else
          for (final server in filtered) ...[
            _ServerSection(
              server: server,
              onKnock: (member) => showKnockSheet(
                context,
                user: member.user,
                activity: member.hima?.activity,
                mood: member.hima?.mood,
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
          ],
      ],
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({required this.server, required this.onKnock});

  final FriendServer server;
  final ValueChanged<FriendMember> onKnock;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              server.guild.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.friendName.copyWith(fontSize: 16),
            ),
          ),
          if (!server.guild.visible) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.purpleSoft,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                '非表示',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
          ],
          Text('${server.members.length}人', style: AppTextStyles.caption),
        ],
      ),
      const SizedBox(height: AppSpacing.s8),
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(
            color: AppColors.purpleSoft,
            width: AppSpacing.borderWidth,
          ),
        ),
        child: Column(
          children: [
            for (var index = 0; index < server.members.length; index++) ...[
              if (index > 0)
                const Divider(height: 1, indent: 16, endIndent: 16),
              _MemberTile(
                member: server.members[index],
                showStatus: server.guild.visible,
                onKnock: () => onKnock(server.members[index]),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.showStatus,
    required this.onKnock,
  });

  final FriendMember member;
  final bool showStatus;
  final VoidCallback onKnock;

  @override
  Widget build(BuildContext context) {
    final hima = member.hima;
    final status = !showStatus
        ? null
        : hima == null
        ? 'いまはひまじゃない'
        : '${hima.mood.emoji} ${hima.activity?.label ?? 'ひま'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s4,
        AppSpacing.s8,
        AppSpacing.s4,
      ),
      child: Row(
        children: [
          AvatarView(
            name: member.user.displayName,
            imageUrl: member.user.avatarUrl,
            size: 40,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.friendName.copyWith(fontSize: 15),
                ),
                if (status != null)
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          if (hima != null)
            KnockPill(friendName: member.user.displayName, onTap: onKnock),
        ],
      ),
    );
  }
}
