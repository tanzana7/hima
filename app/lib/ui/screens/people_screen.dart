import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_view_model.dart';
import '../widgets/common.dart';
import '../widgets/knock_sheet.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  String? _guildFilter;

  Future<void> _showOptions(HimaSession friend) async {
    final shouldHide = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.person_off_outlined),
          title: const Text('この人とはマッチングしない'),
          onTap: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    );
    if (shouldHide != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppViewModel>().addBlock(friend.user.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('設定しました')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('設定できませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final currentActivity = viewModel.myHima?.activity;
    final guilds = viewModel.guilds;
    final friends =
        viewModel.friends.where((friend) {
          return _guildFilter == null || friend.guildIds.contains(_guildFilter);
        }).toList()..sort((a, b) {
          int rank(HimaSession item) =>
              currentActivity == null ||
                  currentActivity == Activity.any ||
                  item.activity == currentActivity ||
                  item.activity == Activity.any
              ? 0
              : 1;
          final byActivity = rank(a).compareTo(rank(b));
          return byActivity == 0
              ? a.user.displayName.compareTo(b.user.displayName)
              : byActivity;
        });

    return PageContent(
      title: 'みんな',
      children: [
        if (guilds.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('すべて'),
                  selected: _guildFilter == null,
                  onSelected: (_) => setState(() => _guildFilter = null),
                ),
                const SizedBox(width: 8),
                for (final guild in guilds) ...[
                  ChoiceChip(
                    label: Text(guild.name),
                    selected: _guildFilter == guild.id,
                    onSelected: (_) => setState(() => _guildFilter = guild.id),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (friends.isEmpty) const EmptyState(message: '今ヒマな友だちはいません。'),
        for (final friend in friends) ...[
          _FriendCard(
            friend: friend,
            onTap: () => showKnockSheet(
              context,
              friend.user,
              quiet: friend.mood == Mood.quiet,
            ),
            onOptions: () => _showOptions(friend),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.onTap,
    required this.onOptions,
  });

  final HimaSession friend;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: InkWell(
      onTap: onTap,
      onLongPress: onOptions,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        child: Row(
          children: [
            InitialAvatar(name: friend.user.displayName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          friend.user.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        friend.mood.emoji,
                        style: const TextStyle(fontSize: 19),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('${friend.activity.emoji} ${friend.activity.label}'),
                  if (friend.note case final note? when note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    remainingLabel(friend.expiresAt),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onOptions,
              tooltip: 'この人の設定',
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      ),
    ),
  );
}
