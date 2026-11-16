import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/avatar_view.dart';
import '../../state/app_view_model.dart';

/// Settings content shared by the プロフィール tab and the header gear route.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.showLogout});

  final bool showLogout;

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
      _showMessage(context, '保存できなかった。もう一度試してね');
    }
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
      _showMessage(context, '保存できなかった。もう一度試してね');
    }
  }

  Future<void> _addBlock(BuildContext context, AppViewModel viewModel) async {
    final blockedIds = viewModel.blocks.map((entry) => entry.user.id).toSet();
    // Built from every shared-server member, not only the currently free ones,
    // so anyone can be opted out of matching.
    final seen = <String>{};
    final candidates = <UserSummary>[
      for (final server in viewModel.friendServers)
        for (final member in server.members)
          if (!blockedIds.contains(member.user.id) &&
              seen.add(member.user.id))
            member.user,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    if (candidates.isEmpty) {
      _showMessage(context, '追加できる人はいないよ');
      return;
    }
    final user = await showModalBottomSheet<UserSummary>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final candidate in candidates)
              ListTile(
                leading: AvatarView(
                  name: candidate.displayName,
                  imageUrl: candidate.avatarUrl,
                  size: 40,
                ),
                title: Text(
                  candidate.displayName,
                  style: AppTextStyles.friendName.copyWith(fontSize: 15),
                ),
                onTap: () => Navigator.of(sheetContext).pop(candidate),
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
      _showMessage(context, '設定できなかった。もう一度試してね');
    }
  }

  Future<void> _removeBlock(BuildContext context, String userId) async {
    try {
      await context.read<AppViewModel>().removeBlock(userId);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '解除できなかった。もう一度試してね');
    }
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final settings = viewModel.me?.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (settings != null) ...[
          _SectionCard(
            children: [
              SwitchListTile(
                title: const Text('自動でひま宣言'),
                value: settings.autoMode,
                onChanged: (value) =>
                    _updateSettings(context, autoMode: value),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  0,
                  AppSpacing.s16,
                  AppSpacing.s12,
                ),
                child: DropdownButtonFormField<Mood>(
                  initialValue: settings.autoMood,
                  isExpanded: true,
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
                    if (mood != null) _updateSettings(context, autoMood: mood);
                  },
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('友達のヒマ宣言を通知'),
                value: settings.notifyOnHima,
                onChanged: (value) =>
                    _updateSettings(context, notifyOnHima: value),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s24),
        ],
        const _SectionHeading('サーバーごとの表示'),
        _SectionCard(
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
              const _SectionNote('共有サーバーはないよ'),
          ],
        ),
        const SizedBox(height: AppSpacing.s24),
        _SectionHeading(
          'マッチングしない人',
          trailing: TextButton.icon(
            onPressed: () => _addBlock(context, viewModel),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('追加'),
          ),
        ),
        _SectionCard(
          children: viewModel.blocks.isEmpty
              ? const [_SectionNote('設定した人はいないよ')]
              : [
                  for (var index = 0; index < viewModel.blocks.length; index++)
                    ListTile(
                      leading: AvatarView(
                        name: viewModel.blocks[index].user.displayName,
                        imageUrl: viewModel.blocks[index].user.avatarUrl,
                        size: 36,
                      ),
                      title: Text(
                        viewModel.blocks[index].user.displayName,
                        style: AppTextStyles.friendName.copyWith(fontSize: 15),
                      ),
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
        ),
        const SizedBox(height: AppSpacing.s24),
        _SectionHeading(
          'よくヒマな時間',
          trailing: IconButton(
            tooltip: '時間を追加',
            onPressed: () => _addSlot(context, viewModel),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        _SectionCard(
          children: viewModel.regularSlots.isEmpty
              ? const [_SectionNote('曜日と時間を登録できるよ')]
              : [
                  for (
                    var index = 0;
                    index < viewModel.regularSlots.length;
                    index++
                  )
                    ListTile(
                      title: Text(_slotLabel(viewModel.regularSlots[index])),
                      trailing: IconButton(
                        tooltip: '削除',
                        onPressed: () => _removeSlot(context, viewModel, index),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                ],
        ),
        const SizedBox(height: AppSpacing.s24),
        _detectionPlaceholder(context),
        if (showLogout) ...[
          const SizedBox(height: AppSpacing.s24),
          OutlinedButton.icon(
            onPressed: () => viewModel.logout(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('ログアウト'),
          ),
        ],
      ],
    );
  }

  Widget _detectionPlaceholder(BuildContext context) => _SectionCard(
    children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.phone_android_rounded, color: AppColors.muted),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xの利用時間から検出',
                    style: AppTextStyles.friendName.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Androidのみ。近日対応予定です。',
                    style: AppTextStyles.caption,
                  ),
                  // TODO: The Android usage-detection task adds the
                  // usage-access flow here.
                ],
              ),
            ),
          ],
        ),
      ),
    ],
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
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s24,
            0,
            AppSpacing.s24,
            AppSpacing.s24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('時間を追加', style: AppTextStyles.sectionTitle),
              const SizedBox(height: AppSpacing.s16),
              DropdownButtonFormField<int>(
                initialValue: weekday,
                isExpanded: true,
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
              const SizedBox(height: AppSpacing.s12),
              _timeSelector(
                label: '開始時刻',
                time: start,
                onChanged: (value) => setSheetState(() => start = value),
              ),
              const SizedBox(height: AppSpacing.s12),
              _timeSelector(
                label: '終了時刻',
                time: end,
                onChanged: (value) => setSheetState(() => end = value),
              ),
              const SizedBox(height: AppSpacing.s24),
              FilledButton(
                onPressed: () {
                  final startMin = start.hour * 60 + start.minute;
                  final endMin = end.hour * 60 + end.minute;
                  if (endMin <= startMin) {
                    _showMessage(sheetContext, '終了時刻は開始時刻より後にしてね');
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
      _showMessage(context, '保存できなかった。もう一度試してね');
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
      _showMessage(context, '削除できなかった。もう一度試してね');
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
        const SizedBox(width: AppSpacing.s12),
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            style: AppTextStyles.friendName.copyWith(fontSize: 17),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
      border: Border.all(
        color: AppColors.purpleSoft,
        width: AppSpacing.borderWidth,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _SectionNote extends StatelessWidget {
  const _SectionNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.s16),
    child: Text(message, style: AppTextStyles.caption),
  );
}
