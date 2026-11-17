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
import '../../shared/widgets/paint/paint.dart';
import '../../state/app_view_model.dart';
import '../knocks/widgets/knock_sheet.dart';

/// Captions that sit directly on a [PaintWash]. [AppColors.muted] measures
/// 4.2:1 once the wash layers overlap, so text on paint takes this darker tone
/// instead (5.4:1).
const _washMuted = Color(0xFF635B6F);

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
        const _ScreenHeader(),
        const SizedBox(height: AppSpacing.s12),
        _searchField(),
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

  /// The field is a soft wash with no outline. A focus ring would put back the
  /// hairline the rest of the screen just lost, so focus is shown by the caret
  /// and by the text the user is typing.
  Widget _searchField() => PaintWash(
    seed: paintSeedOf('friends-search'),
    color: AppColors.purpleSoft,
    // Zero padding: the field's own content padding keeps the text off the
    // paint's edge, and the wash is then exactly the field's box.
    padding: EdgeInsets.zero,
    corner: AppSpacing.radiusPill,
    // The pooling rim reads as an outline at this size, which is the one thing
    // the field is losing.
    rim: false,
    child: TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: '名前でさがす',
        hintStyle: AppTextStyles.body.copyWith(color: _washMuted),
        // The wash is the field's background, so the theme's fill and its
        // outline borders are both turned off.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: 14,
        ),
        prefixIcon: const Icon(Icons.search_rounded, color: _washMuted),
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
  );
}

/// The tab title with a brush-stroke underline and a flick of paint, the same
/// header the home screen uses for its sections.
class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('友達', style: AppTextStyles.sectionTitle),
            BrushStroke(
              seed: 61,
              size: const Size(84, 9),
              color: AppColors.purple.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
      const SplatterDots(
        seed: 67,
        size: Size(22, 18),
        color: AppColors.coral,
        count: 5,
      ),
    ],
  );
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({required this.server, required this.onKnock});

  final FriendServer server;
  final ValueChanged<FriendMember> onKnock;

  /// The group's hue, picked from the guild id so a server keeps its colour
  /// across rebuilds and the list does not look striped.
  Color get _tint =>
      AppColors.friendTints[paintSeedOf(server.guild.id) %
          AppColors.friendTints.length];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  server.guild.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.friendName.copyWith(fontSize: 16),
                ),
                BrushStroke(
                  seed: paintSeedOf('guild-stroke-${server.guild.id}'),
                  size: const Size(88, 8),
                  color: paintTone(_tint, -0.3),
                ),
              ],
            ),
          ),
          if (!server.guild.visible) ...[
            PaintDab(
              seed: paintSeedOf('guild-hidden-${server.guild.id}'),
              color: AppColors.purpleSoft,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: 3,
              ),
              child: Text(
                '非表示',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.ink,
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
      // One wash for the whole group instead of a bordered white box: the wash
      // is the group's edge, and the rows are separated by spacing rather than
      // by dividers. A wash per row would double the paint and cost a
      // RepaintBoundary per row while scrolling.
      PaintWash(
        seed: paintSeedOf('guild-${server.guild.id}'),
        color: _tint,
        padding: const EdgeInsets.all(AppSpacing.s8),
        corner: AppSpacing.radiusCard,
        child: Column(
          children: [
            for (var index = 0; index < server.members.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.s4),
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
        AppSpacing.s8,
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
                    style: AppTextStyles.caption.copyWith(color: _washMuted),
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
