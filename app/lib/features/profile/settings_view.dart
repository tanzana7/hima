import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/hima_suggest_bridge.dart';
import '../../data/models/models.dart';
import '../../shared/haptics.dart';
import '../../shared/phrase_wrap.dart';
import '../../shared/widgets/avatar_view.dart';
import '../../shared/widgets/paint/paint.dart';
import '../../shared/widgets/paint_button.dart';
import '../../shared/widgets/shake.dart';
import '../../state/app_view_model.dart';
import '../../state/hima_suggest_controller.dart';
import '../../state/session_owner.dart';

/// Captions that sit directly on a [PaintWash]. [AppColors.muted] measures
/// 4.2:1 on the pastel wash, so text on paint takes this darker tone instead
/// (5.4:1).
const _washMuted = Color(0xFF635B6F);

/// The 「自動ひま提案」 description: one clause per line, and inside each clause
/// the line may turn only between its phrases.
///
/// Without the phrase boundaries a large text scale broke the second clause as
/// 「いつもの時間に通知す／るよ」, leaving 「るよ」 alone on its own line.
final String _suggestDescription = [
  wrapPhrases(['使い続けた', 'ときと、']),
  wrapPhrases(['いつもの時間に', '通知するよ']),
].join('\n');

/// The 「Discordでも受け取る」 switch label: two phrases, so a large text scale
/// wraps before 「受け取る」 instead of splitting it.
final String _suggestDmTitle = wrapPhrases(['Discordでも', '受け取る']);

/// Settings content shared by the プロフィール tab and the header gear route.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.showLogout});

  final bool showLogout;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The device state is not part of /app/me, so the section has to read it
    // when it appears.
    unawaited(context.read<HimaSuggestController>().load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // A permission is granted in system settings, so the row that asked for it
    // only goes away once the app is back.
    unawaited(context.read<HimaSuggestController>().load());
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
    final suggest = _suggestSection(context, viewModel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (suggest != null) ...[
          suggest,
          const SizedBox(height: AppSpacing.s24),
        ],
        const _SectionHeading('サーバーごとの表示'),
        _SectionCard(
          seed: paintSeedOf('settings-guilds'),
          color: AppColors.skySoft,
          children: [
            for (var index = 0; index < viewModel.guilds.length; index++)
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
            if (viewModel.guilds.isEmpty) const _SectionNote('共有サーバーはないよ'),
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
          seed: paintSeedOf('settings-blocks'),
          color: AppColors.peachSoft,
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
          seed: paintSeedOf('settings-slots'),
          color: AppColors.mintSoft,
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
        if (widget.showLogout) ...[
          PaintButton(
            seed: 991,
            label: 'ログアウト',
            icon: Icons.logout_rounded,
            color: AppColors.purpleSoft,
            foreground: AppColors.ink,
            onPressed: () => viewModel.logout(),
          ),
        ],
        // A developer tool, kept out of the release build and out of the demo
        // session itself; `showDemoEntry` is the one place that decides.
        if (context.read<SessionOwner>().showDemoEntry) ...[
          const SizedBox(height: AppSpacing.s24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('デモモード'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => unawaited(context.read<SessionOwner>().enterDemo()),
          ),
        ],
      ],
    );
  }

  /// Keeps the suggestion switch and its description readable at large scales.
  Widget _suggestSwitchControl(
    BuildContext context,
    bool enabled,
    ValueChanged<bool> onChanged,
  ) {
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (textScale < 1.4) {
      return SwitchListTile(
        title: const Text('自動ひま提案'),
        subtitle: Text(
          _suggestDescription,
          semanticsLabel: plainPhrases(_suggestDescription),
        ),
        value: enabled,
        onChanged: onChanged,
      );
    }

    // SwitchListTile reserves the switch width for its subtitle too, which
    // leaves punctuation stranded at 200%. Put the full-width copy below the
    // title and switch; the InkWell keeps the whole row tappable and
    // MergeSemantics keeps one labelled control for readers.
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!enabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '自動ひま提案',
                      style:
                          Theme.of(context).listTileTheme.titleTextStyle ??
                          Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Switch(value: enabled, onChanged: onChanged),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                _suggestDescription,
                semanticsLabel: plainPhrases(_suggestDescription),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The 「自動ひま提案」 card, or null where the native worker does not exist.
  ///
  /// The worker is device state, so it is read from the bridge instead of
  /// `/app/me`: it lives in Android, and the server cannot describe it. Only
  /// 「Discordでも受け取る」 comes from the server's `suggest_dm`.
  Widget? _suggestSection(BuildContext context, AppViewModel viewModel) {
    final suggest = context.watch<HimaSuggestController>();
    if (!suggest.isSupported) return null;
    // `/app/me` carries the flag; settings missing from the payload mean the
    // server's default.
    final suggestDm =
        viewModel.me?.settings.suggestDm ?? UserSettings.fallback.suggestDm;
    return _SectionCard(
      seed: paintSeedOf('settings-suggest'),
      color: AppColors.purpleSoft,
      children: [
        _SavingControl<bool>(
          value: suggest.enabled,
          onSave: (value) => _setSuggestEnabled(context, value),
          builder: (context, enabled, onChanged) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _suggestSwitchControl(context, enabled, onChanged),
              if (enabled) ...[
                // Only meaningful while the worker can fire: the switch exists
                // to stop the server saying the same thing over Discord.
                _SavingControl<bool>(
                  value: suggestDm,
                  onSave: (value) => _setSuggestDm(context, value),
                  builder: (context, value, onChanged) => SwitchListTile(
                    title: Text(
                      _suggestDmTitle,
                      semanticsLabel: plainPhrases(_suggestDmTitle),
                    ),
                    value: value,
                    onChanged: onChanged,
                  ),
                ),
                if (!suggest.usageAccess)
                  ListTile(
                    title: const Text('使用状況へのアクセス'),
                    trailing: TextButton(
                      onPressed: () => _openUsageAccess(context),
                      child: const Text('許可'),
                    ),
                  ),
                if (!suggest.notificationsAllowed)
                  ListTile(
                    title: const Text('通知'),
                    trailing: TextButton(
                      onPressed: () => _allowNotifications(context),
                      child: const Text('許可'),
                    ),
                  ),
                _SavingControl<int>(
                  value: suggest.appTriggerMinutes,
                  onSave: (minutes) =>
                      _setSuggestTriggerMinutes(context, minutes),
                  builder: (context, minutes, onChanged) => ListTile(
                    // Body size rather than the tile's 16sp default: the label
                    // is long, and the smaller size is what keeps it on one
                    // line at 200% text on a 360dp phone.
                    title: const Text(
                      '通知までの利用時間',
                      style: AppTextStyles.body,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s8),
                      child: Wrap(
                        // Wraps rather than shrinks: four pills do not fit one
                        // line at 360dp and 200% text, and a Row would overflow.
                        spacing: AppSpacing.s8,
                        runSpacing: AppSpacing.s8,
                        children: [
                          for (final option in himaSuggestTriggerMinuteChoices)
                            _TriggerMinutesChoice(
                              label: durationLabel(option),
                              selected: option == minutes,
                              onTap: () => onChanged(option),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final target in suggest.targets)
                  ListTile(
                    // Rich text so 「未インストール」 wraps under the label at a
                    // large text scale instead of pushing the row wider.
                    title: Text.rich(
                      TextSpan(
                        text: target.label,
                        children: [
                          if (!target.installed)
                            TextSpan(
                              text: '  未インストール',
                              style: AppTextStyles.caption.copyWith(
                                color: _washMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: '外す',
                      onPressed: () => _removeTarget(context, target),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ListTile(
                  title: const Text('アプリを追加'),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => _addTarget(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Turns the suggestion worker on or off.
  ///
  /// The device switch is the source of truth, and the same tap also flips
  /// `suggest_dm`: the worker and the server's suggestion would otherwise tell
  /// the user the same thing twice. `auto_mode` is still written so the server
  /// keeps a compatible value, but nothing reads it any more.
  ///
  /// A failed settings write must not undo the switch: the device state already
  /// changed, so the switch stays as flipped and only the failure is reported.
  Future<bool> _setSuggestEnabled(BuildContext context, bool value) async {
    final suggest = context.read<HimaSuggestController>();
    final viewModel = context.read<AppViewModel>();
    try {
      await suggest.setEnabled(value);
    } catch (_) {
      if (!context.mounted) return false;
      AppHaptics.error();
      _showMessage(context, '保存できなかった。もう一度試してね');
      return false;
    }
    // Turning the worker on hands the Discord side over to it; turning it off
    // gives Discord its suggestions back so the user keeps getting them.
    unawaited(
      viewModel
          .updateSettings(autoMode: value, suggestDm: !value)
          .catchError((Object _) {
            if (!context.mounted) return;
            AppHaptics.error();
            _showMessage(context, '保存できなかった。もう一度試してね');
          }),
    );
    if (value && !suggest.notificationsAllowed) {
      // Asked right away: without the permission the worker is silent, and the
      // user is already on the screen that explains it.
      try {
        await suggest.requestNotificationPermission();
      } catch (_) {
        // The 「通知」 row stays, so 許可 can be pressed again.
      }
    }
    return true;
  }

  /// Stores whether the server may also suggest over Discord (and push).
  Future<bool> _setSuggestDm(BuildContext context, bool value) async {
    try {
      await context.read<AppViewModel>().updateSettings(suggestDm: value);
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      AppHaptics.error();
      _showMessage(context, '保存できなかった。もう一度試してね');
      return false;
    }
  }

  /// Stores how long the target apps must be used before a suggestion.
  Future<bool> _setSuggestTriggerMinutes(
    BuildContext context,
    int minutes,
  ) async {
    try {
      await context.read<HimaSuggestController>().setAppTriggerMinutes(minutes);
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      AppHaptics.error();
      _showMessage(context, '保存できなかった。もう一度試してね');
      return false;
    }
  }

  Future<void> _openUsageAccess(BuildContext context) async {
    try {
      await context.read<HimaSuggestController>().openUsageAccessSettings();
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '開けなかった。もう一度試してね');
    }
  }

  Future<void> _allowNotifications(BuildContext context) async {
    final suggest = context.read<HimaSuggestController>();
    try {
      await suggest.requestNotificationPermission();
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '許可できなかった。もう一度試してね');
    }
  }

  Future<void> _removeTarget(
    BuildContext context,
    HimaSuggestTarget target,
  ) async {
    final suggest = context.read<HimaSuggestController>();
    // The list is the display order, so the remaining packages keep theirs.
    final packages = [
      for (final item in suggest.targets)
        if (item.package != target.package) item.package,
    ];
    try {
      await suggest.setTargets(packages);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '外せなかった。もう一度試してね');
    }
  }

  Future<void> _addTarget(BuildContext context) async {
    final suggest = context.read<HimaSuggestController>();
    final packages = [for (final target in suggest.targets) target.package];
    final added = await showModalBottomSheet<HimaSuggestApp>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => _AddAppSheet(
        targeted: packages.toSet(),
        loadApps: suggest.listLaunchableApps,
      ),
    );
    if (added == null || !context.mounted) return;
    try {
      await suggest.setTargets([...packages, added.package]);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '追加できなかった。もう一度試してね');
    }
  }

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

/// The 「アプリを追加」 sheet: the templates first, then every other launchable
/// app behind a search field.
class _AddAppSheet extends StatefulWidget {
  const _AddAppSheet({required this.targeted, required this.loadApps});

  /// Packages already in the target list; they are not offered again.
  final Set<String> targeted;

  final Future<List<HimaSuggestApp>> Function() loadApps;

  @override
  State<_AddAppSheet> createState() => _AddAppSheetState();
}

class _AddAppSheetState extends State<_AddAppSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Read once per sheet: the app list cannot change while the sheet is open.
  late final Future<List<HimaSuggestApp>> _apps = widget.loadApps();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Every launchable app that is not offered above or already a target.
  List<HimaSuggestApp> _matches(List<HimaSuggestApp> apps) {
    final query = _query.trim().toLowerCase();
    return [
      for (final app in apps)
        if (!widget.targeted.contains(app.package) &&
            !himaSuggestTemplates.any(
              (template) => template.package == app.package,
            ) &&
            (query.isEmpty || app.label.toLowerCase().contains(query)))
          app,
    ];
  }

  void _choose(HimaSuggestApp app) => Navigator.of(context).pop(app);

  @override
  Widget build(BuildContext context) => Padding(
    // The keyboard would otherwise cover the search field at the bottom of the
    // sheet.
    padding: EdgeInsets.fromLTRB(
      AppSpacing.s24,
      0,
      AppSpacing.s24,
      AppSpacing.s24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        const Text('アプリを追加', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.s8),
        for (final template in himaSuggestTemplates)
          if (!widget.targeted.contains(template.package))
            ListTile(
              title: Text(template.label),
              onTap: () => _choose(template),
            ),
        const SizedBox(height: AppSpacing.s8),
        PaintDab(
          seed: paintSeedOf('suggest-search'),
          color: AppColors.purpleSoft,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: 6,
          ),
          wobble: 0.10,
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'アプリ名でさがす',
              hintStyle: AppTextStyles.body.copyWith(color: _washMuted),
              // The dab is the field's background, so the theme's fill and
              // borders are both turned off, like the friends search field.
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.search_rounded, color: _washMuted),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        FutureBuilder<List<HimaSuggestApp>>(
          future: _apps,
          builder: (context, snapshot) {
            final apps = snapshot.data;
            if (apps == null) {
              // The templates above are already usable, so a slow or failed
              // read never blocks adding X or YouTube.
              return snapshot.connectionState == ConnectionState.waiting
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.s16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const _SectionNote('アプリの一覧を読み込めなかったよ');
            }
            final matches = _matches(apps);
            if (matches.isEmpty) {
              return const _SectionNote('追加できるアプリはないよ');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final app in matches)
                  ListTile(
                    title: Text(app.label),
                    onTap: () => _choose(app),
                  ),
              ],
            );
          },
        ),
      ],
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

/// One length offered by 「通知までの利用時間」.
///
/// A pill instead of another row: four rows would push the app list far down,
/// and the surrounding [Wrap] breaks the pills into lines rather than
/// overflowing. The pill is as tall as the design's minimum tap target, and the
/// selected one is a filled pill, not only a bolder label, so the choice is
/// visible without relying on colour alone.
class _TriggerMinutesChoice extends StatelessWidget {
  const _TriggerMinutesChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    // `excludeSemantics` drops the InkWell below, including its tap action, so
    // the node has to carry the action itself or the choice is unreachable for
    // screen reader users.
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.minTapTarget,
          minWidth: AppSpacing.minTapTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.purpleSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? AppColors.purple : AppColors.purpleSoft,
            width: AppSpacing.borderWidth,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? AppColors.purple : AppColors.ink,
          ),
        ),
      ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                style: AppTextStyles.friendName.copyWith(fontSize: 17),
              ),
              // A brush stroke under the heading, the same underline the home
              // screen's sections carry.
              BrushStroke(
                seed: paintSeedOf('settings-heading-$title'),
                size: const Size(96, 8),
                color: AppColors.purple.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A settings group: a soft wash instead of a bordered white box, with the rows
/// separated by spacing rather than by dividers.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.seed,
    required this.color,
    required this.children,
  });

  final int seed;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => PaintWash(
    seed: seed,
    color: color,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s8,
      vertical: AppSpacing.s8,
    ),
    corner: AppSpacing.radiusCard,
    child: Column(
      // Stretch so a note fills the wash and reads left-aligned instead of
      // floating in the middle of the paint.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.s4),
          children[index],
        ],
      ],
    ),
  );
}

class _SectionNote extends StatelessWidget {
  const _SectionNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.s16),
    child: Text(
      message,
      style: AppTextStyles.caption.copyWith(color: _washMuted),
    ),
  );
}
