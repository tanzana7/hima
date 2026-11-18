import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/hima_suggest_bridge.dart';
import '../../data/models/models.dart';
import '../../shared/haptics.dart';
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
    final suggest = _suggestSection(context);
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

  /// The 「自動ひま提案」 card, or null where the native worker does not exist.
  ///
  /// Everything here is device state, so it is read from the bridge instead of
  /// `/app/me`: the worker lives in Android, and the server cannot describe it.
  Widget? _suggestSection(BuildContext context) {
    final suggest = context.watch<HimaSuggestController>();
    if (!suggest.isSupported) return null;
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
              SwitchListTile(
                title: const Text('自動ひま提案'),
                // Two clauses with an explicit break: Japanese wraps at any
                // character, so a greedy wrap split words (「提案」 left 「案」
                // alone on a third line, and a shorter copy split 「ときと」).
                // Each clause stays at 12 characters or fewer so it fits one
                // line on a 360dp phone; at a larger text scale each clause
                // wraps on its own instead of mid-word across the comma.
                subtitle: const Text('対象アプリの利用中と、\nいつもの時間に通知するよ'),
                value: enabled,
                onChanged: onChanged,
              ),
              if (enabled) ...[
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
  /// `auto_mode` is still written so the server keeps a compatible value, but
  /// nothing reads it any more: a failed write must not look like a failure to
  /// the user who just flipped the device switch.
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
    unawaited(
      viewModel.updateSettings(autoMode: value).catchError((Object _) {}),
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
