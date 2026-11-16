import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_view_model.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _updateSettings(
    BuildContext context, {
    bool? autoMode,
    Mood? autoMood,
    bool? notifyOnHima,
  }) async {
    try {
      await context.read<AppViewModel>().updateSettings(
        autoMode: autoMode,
        autoMood: autoMood,
        notifyOnHima: notifyOnHima,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度お試しください。')));
    }
  }

  Future<void> _addBlock(BuildContext context, AppViewModel viewModel) async {
    final blockedIds = viewModel.blocks.map((entry) => entry.user.id).toSet();
    final candidates = viewModel.friends
        .where((friend) => !blockedIds.contains(friend.user.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('追加できる人はいません。')));
      return;
    }
    final user = await showModalBottomSheet<UserSummary>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final friend in candidates)
              ListTile(
                leading: InitialAvatar(name: friend.user.displayName, size: 40),
                title: Text(friend.user.displayName),
                onTap: () => Navigator.of(sheetContext).pop(friend.user),
              ),
          ],
        ),
      ),
    );
    if (user == null || !context.mounted) return;
    try {
      await viewModel.addBlock(user.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('設定できませんでした。もう一度お試しください。')));
    }
  }

  Future<void> _removeBlock(BuildContext context, String userId) async {
    try {
      await context.read<AppViewModel>().removeBlock(userId);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('解除できませんでした。もう一度お試しください。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final settings = viewModel.me?.settings;
    return PageContent(
      title: '設定',
      children: [
        if (settings != null)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('自動でヒマ宣言'),
                  value: settings.autoMode,
                  onChanged: (value) =>
                      _updateSettings(context, autoMode: value),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: DropdownButtonFormField<Mood>(
                    initialValue: settings.autoMood,
                    decoration: const InputDecoration(labelText: '自動宣言の温度感'),
                    items: Mood.values
                        .map(
                          (mood) => DropdownMenuItem(
                            value: mood,
                            child: Text('${mood.emoji} ${mood.label}'),
                          ),
                        )
                        .toList(),
                    onChanged: (mood) {
                      if (mood != null) {
                        _updateSettings(context, autoMood: mood);
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('友だちのヒマ宣言を通知'),
                  value: settings.notifyOnHima,
                  onChanged: (value) =>
                      _updateSettings(context, notifyOnHima: value),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const SectionTitle('サーバーごとの表示'),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              for (var index = 0; index < viewModel.guilds.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: Text(viewModel.guilds[index].name),
                  value: viewModel.guilds[index].visible,
                  onChanged: (visible) => _setGuildVisibility(
                    context,
                    viewModel.guilds[index].id,
                    visible,
                  ),
                ),
              ],
              if (viewModel.guilds.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('共有サーバーはありません。'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionTitle(
          'マッチングしない人',
          trailing: TextButton.icon(
            onPressed: () => _addBlock(context, viewModel),
            icon: const Icon(Icons.add_rounded),
            label: const Text('追加'),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: viewModel.blocks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('設定した人はいません。'),
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < viewModel.blocks.length;
                      index++
                    ) ...[
                      if (index > 0)
                        const Divider(height: 1, indent: 16, endIndent: 8),
                      ListTile(
                        title: Text(viewModel.blocks[index].user.displayName),
                        trailing: IconButton(
                          tooltip: '解除',
                          onPressed: () => _removeBlock(
                            context,
                            viewModel.blocks[index].user.id,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 24),
        SectionTitle(
          'よくヒマな時間',
          trailing: IconButton(
            tooltip: '時間を追加',
            onPressed: () => _addSlot(context, viewModel),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: viewModel.regularSlots.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('曜日と時間を登録できます。'),
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < viewModel.regularSlots.length;
                      index++
                    ) ...[
                      if (index > 0)
                        const Divider(height: 1, indent: 16, endIndent: 8),
                      ListTile(
                        title: Text(_slotLabel(viewModel.regularSlots[index])),
                        trailing: IconButton(
                          tooltip: '削除',
                          onPressed: () =>
                              _removeSlot(context, viewModel, index),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 24),
        _detectionPlaceholder(context),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => viewModel.logout(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('ログアウト'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
      ],
    );
  }

  Future<void> _setGuildVisibility(
    BuildContext context,
    String guildId,
    bool visible,
  ) async {
    try {
      await context.read<AppViewModel>().updateGuildVisibility(
        guildId,
        visible,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度お試しください。')));
    }
  }

  Widget _detectionPlaceholder(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.phone_android_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xの利用時間から検出',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Androidのみ。近日対応予定です。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                // TODO: The Android usage-detection task adds the usage-access flow here.
              ],
            ),
          ),
        ],
      ),
    ),
  );

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  static String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  static String _slotLabel(RegularSlot slot) =>
      '${_weekdays[slot.weekday]} ${_clock(slot.startMin)}–${_clock(slot.endMin)}';

  Future<void> _addSlot(BuildContext context, AppViewModel viewModel) async {
    var weekday = 0;
    var start = const TimeOfDay(hour: 19, minute: 0);
    var end = const TimeOfDay(hour: 21, minute: 0);
    final slot = await showModalBottomSheet<RegularSlot>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('時間を追加', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: weekday,
                decoration: const InputDecoration(labelText: '曜日'),
                items: List.generate(
                  7,
                  (day) =>
                      DropdownMenuItem(value: day, child: Text(_weekdays[day])),
                ),
                onChanged: (value) {
                  if (value != null) setSheetState(() => weekday = value);
                },
              ),
              const SizedBox(height: 12),
              _timeSelector(
                label: '開始時刻',
                time: start,
                onChanged: (value) => setSheetState(() => start = value),
              ),
              const SizedBox(height: 12),
              _timeSelector(
                label: '終了時刻',
                time: end,
                onChanged: (value) => setSheetState(() => end = value),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  final startMin = start.hour * 60 + start.minute;
                  final endMin = end.hour * 60 + end.minute;
                  if (endMin <= startMin) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(content: Text('終了時刻は開始時刻より後にしてください。')),
                    );
                    return;
                  }
                  Navigator.of(sheetContext).pop(
                    RegularSlot(
                      weekday: weekday,
                      startMin: startMin,
                      endMin: endMin,
                    ),
                  );
                },
                child: const Text('追加'),
              ),
            ],
          ),
        ),
      ),
    );
    if (slot == null || !context.mounted) return;
    final updated = [...viewModel.regularSlots, slot]
      ..sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        return byDay == 0 ? a.startMin.compareTo(b.startMin) : byDay;
      });
    try {
      await viewModel.saveRegularSlots(updated);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度お試しください。')));
    }
  }

  Future<void> _removeSlot(
    BuildContext context,
    AppViewModel viewModel,
    int index,
  ) async {
    final updated = [...viewModel.regularSlots]..removeAt(index);
    try {
      await viewModel.saveRegularSlots(updated);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('削除できませんでした。もう一度お試しください。')));
    }
  }

  Widget _timeSelector({
    required String label,
    required TimeOfDay time,
    required ValueChanged<TimeOfDay> onChanged,
  }) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: Row(
      children: [
        Expanded(
          child: DropdownButton<int>(
            value: time.hour,
            isExpanded: true,
            menuMaxHeight: 320,
            underline: const SizedBox.shrink(),
            items: List.generate(
              24,
              (hour) => DropdownMenuItem(
                value: hour,
                child: Text('${hour.toString().padLeft(2, '0')}時'),
              ),
            ),
            onChanged: (hour) {
              if (hour != null) {
                onChanged(TimeOfDay(hour: hour, minute: time.minute));
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<int>(
            value: time.minute,
            isExpanded: true,
            menuMaxHeight: 320,
            underline: const SizedBox.shrink(),
            items: List.generate(
              60,
              (minute) => DropdownMenuItem(
                value: minute,
                child: Text('${minute.toString().padLeft(2, '0')}分'),
              ),
            ),
            onChanged: (minute) {
              if (minute != null) {
                onChanged(TimeOfDay(hour: time.hour, minute: minute));
              }
            },
          ),
        ),
      ],
    ),
  );
}
