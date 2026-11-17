import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/models/models.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/avatar_view.dart';
import '../../shared/widgets/shake.dart';
import '../../state/app_view_model.dart';

/// Settings content shared by the プロフィール tab and the header gear route.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.showLogout});

  final bool showLogout;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  /// Saves a setting and reports whether it was stored.
  ///
  /// The error haptic and the message live here so every settings control fails
  /// the same way; the control that failed shakes itself.
  Future<bool> _updateSettings(
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
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      AppHaptics.error();
      _showMessage(context, '保存できなかった。もう一度試してね');
      return false;
    }
  }

  Future<bool> _setGuildVisibility(
    BuildContext context,
    String guildId,
    bool visible,
  ) async {
    try {
      await context.read<AppViewModel>().updateGuildVisibility(
        guildId,
        visible,
      );
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      AppHaptics.error();
      _showMessage(context, '保存できなかった。もう一度試してね');
      return false;
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
              _SavingControl<bool>(
                value: settings.autoMode,
                onSave: (value) => _updateSettings(context, autoMode: value),
                builder: (context, autoMode, onChanged) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      title: const Text('自動でひま宣言'),
                      value: autoMode,
                      onChanged: onChanged,
                    ),
                    // The mood only matters while auto mode is on, so it folds
                    // away instead of sitting there as a dead control.
                    AnimatedSize(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: autoMode
                          ? _AutoMoodChips(
                              mood: settings.autoMood,
                              onSave: (mood) =>
                                  _updateSettings(context, autoMood: mood),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _SavingControl<bool>(
                value: settings.notifyOnHima,
                onSave: (value) =>
                    _updateSettings(context, notifyOnHima: value),
                builder: (context, value, onChanged) => SwitchListTile(
                  title: const Text('友達のひま宣言を通知'),
                  value: value,
                  onChanged: onChanged,
                ),
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
              _SavingControl<bool>(
                // Keyed so a guild leaving the list cannot hand its draft to the
                // row that slides into its place.
                key: ValueKey(viewModel.guilds[index].id),
                value: viewModel.guilds[index].visible,
                onSave: (visible) => _setGuildVisibility(
                  context,
                  viewModel.guilds[index].id,
                  visible,
                ),
                builder: (context, value, onChanged) => SwitchListTile(
                  title: Text(viewModel.guilds[index].name),
                  value: value,
                  onChanged: onChanged,
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
          'よくひまな時間',
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
                        onPressed: () => _removeSlot(
                          context,
                          viewModel,
                          viewModel.regularSlots[index],
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                ],
        ),
        const SizedBox(height: AppSpacing.s24),
        _detectionPlaceholder(context),
        if (widget.showLogout) ...[
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

  static String _slotLabel(RegularSlot slot) =>
      '${weekdayLabels[slot.weekday]} ${clockLabel(slot.startMin)}–${clockLabel(slot.endMin)}';

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
                  (day) => DropdownMenuItem(
                    value: day,
                    child: Text(weekdayLabels[day]),
                  ),
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
    try {
      // Slots are added one at a time; the server assigns the id the row needs
      // to be deleted again.
      await viewModel.addRegularSlot(slot);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '保存できなかった。もう一度試してね');
    }
  }

  Future<void> _removeSlot(
    BuildContext context,
    AppViewModel viewModel,
    RegularSlot slot,
  ) async {
    try {
      await viewModel.deleteRegularSlot(slot);
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

/// The 自動宣言の温度感 choice, shown only while auto mode is on.
class _AutoMoodChips extends StatelessWidget {
  const _AutoMoodChips({required this.mood, required this.onSave});

  final Mood mood;
  final Future<bool> Function(Mood mood) onSave;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      0,
      AppSpacing.s16,
      AppSpacing.s12,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('自動宣言の温度感', style: AppTextStyles.caption),
        const SizedBox(height: AppSpacing.s8),
        _SavingControl<Mood>(
          value: mood,
          onSave: onSave,
          builder: (context, value, onChanged) =>
              _MoodChips(selected: value, onSelected: onChanged),
        ),
      ],
    ),
  );
}

/// The three auto-declaration moods as compact chips. The full mood names are
/// too long to sit side by side, so each chip carries the emoji plus a short
/// label and keeps the full name as its accessible label.
class _MoodChips extends StatelessWidget {
  const _MoodChips({required this.selected, required this.onSelected});

  final Mood selected;
  final ValueChanged<Mood> onSelected;

  static String _shortLabel(Mood mood) => switch (mood) {
    Mood.fire => '今すぐ',
    Mood.ok => '誘い待ち',
    Mood.quiet => 'ひっそり',
  };

  /// Full name for screen readers. `Mood.label` still spells ひま as 暇, and the
  /// app writes it in hiragana everywhere, so the spoken name is spelled here.
  static String _semanticLabel(Mood mood) => switch (mood) {
    Mood.fire => '今すぐ遊びたい',
    Mood.ok => '誘われたら行く',
    Mood.quiet => 'ひっそりひま',
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.s8,
    runSpacing: AppSpacing.s8,
    children: [
      for (final mood in Mood.values)
        _MoodChip(
          mood: mood,
          label: _shortLabel(mood),
          semanticLabel: _semanticLabel(mood),
          selected: mood == selected,
          onTap: () {
            if (mood == selected) return;
            AppHaptics.select();
            onSelected(mood);
          },
        ),
    ],
  );
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({
    required this.mood,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final Mood mood;
  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${mood.emoji} $semanticLabel',
    // The child's semantics are excluded, so the wrapper has to carry the
    // action itself or the chip cannot be activated by a screen reader.
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.purpleSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? AppColors.purple : AppColors.purpleSoft,
            width: AppSpacing.borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mood.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: AppSpacing.s4 + 2),
            Text(
              label,
              maxLines: 1,
              style: AppTextStyles.body.copyWith(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.ink : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A settings control that only keeps the value the user picked once it is
/// stored.
///
/// The picked value is shown immediately so the control feels responsive, but it
/// is dropped again when saving fails: the control falls back to the stored
/// value and shakes, so a failed save never looks like a success.
class _SavingControl<T> extends StatefulWidget {
  const _SavingControl({
    super.key,
    required this.value,
    required this.onSave,
    required this.builder,
  });

  final T value;

  /// Returns true when the value reached the server.
  final Future<bool> Function(T value) onSave;

  final Widget Function(
    BuildContext context,
    T value,
    ValueChanged<T> onChanged,
  ) builder;

  @override
  State<_SavingControl<T>> createState() => _SavingControlState<T>();
}

class _SavingControlState<T> extends State<_SavingControl<T>> {
  final GlobalKey<ShakeState> _shakeKey = GlobalKey<ShakeState>();
  late T _shown = widget.value;

  @override
  void didUpdateWidget(_SavingControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the stored value whenever it changes from the outside.
    if (widget.value != oldWidget.value) _shown = widget.value;
  }

  Future<void> _handleChanged(T value) async {
    setState(() => _shown = value);
    final saved = await widget.onSave(value);
    if (!mounted) return;
    if (!saved) {
      setState(() => _shown = widget.value);
      _shakeKey.currentState?.shake();
    }
  }

  @override
  Widget build(BuildContext context) => Shake(
    key: _shakeKey,
    child: widget.builder(context, _shown, _handleChanged),
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
