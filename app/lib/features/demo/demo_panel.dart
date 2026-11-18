import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/login_screen.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/demo_hima_suggest_bridge.dart';
import '../../data/hima_suggest_bridge.dart';
import '../../data/mock_api_client.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/brush_title.dart';
import '../../shared/widgets/paint/paint.dart';
import '../../shared/widgets/paint_button.dart';
import '../../state/app_view_model.dart';
import '../../state/hima_suggest_controller.dart';
import '../../state/session_owner.dart';
import '../home/hero_picks.dart';
import '../home/widgets/pickers.dart';
import '../knocks/knocks_screen.dart';
import '../knocks/widgets/knock_sheet.dart';
import '../profile/settings_screen.dart';

/// Opens the catalog over whatever is on screen.
///
/// The floating entry point sits above the navigator, so it has no route to push
/// from; the demo session's key is the handle that is still valid there.
void openDemoPanel(DemoSession demo) {
  final navigator = demo.navigatorKey.currentState;
  if (navigator == null) return;
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => DemoPanel(demo: demo)),
  );
}

/// Every screen, sheet and state of the app in one page.
///
/// It exists inside the demo session only, where the view model, the suggest
/// controller and the mock are the demo ones, so opening a screen here shows
/// mock data without touching the real session.
class DemoPanel extends StatefulWidget {
  const DemoPanel({super.key, required this.demo});

  final DemoSession demo;

  @override
  State<DemoPanel> createState() => _DemoPanelState();
}

class _DemoPanelState extends State<DemoPanel> {
  late final AppViewModel _viewModel = widget.demo.viewModel;
  late final MockApiClient _api = widget.demo.api;
  late final DemoHimaSuggestBridge _bridge = widget.demo.bridge;
  late final HimaSuggestController _suggest = widget.demo.suggest;

  @override
  void initState() {
    super.initState();
    // After the frame: the floating entry point is an ancestor of every route,
    // and notifying it from inside a build would rebuild it mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.demo.panelVisible.value = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.demo.panelVisible.value = false;
    });
    super.dispose();
  }

  NavigatorState get _navigator => Navigator.of(context);

  /// Moves the shell to one of its tabs. The panel goes away with it, the way a
  /// catalog entry does.
  void _selectTab(int index) {
    _navigator.popUntil((route) => route.isFirst);
    widget.demo.tabs.value = index;
  }

  void _push(WidgetBuilder builder) {
    final navigator = _navigator;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(MaterialPageRoute<void>(builder: builder));
  }

  void _openLogin() {
    final owner = context.read<SessionOwner>();
    _push((_) => LoginScreen(config: owner.config));
  }

  /// Runs [show] over the shell rather than over this page.
  ///
  /// The catalog closes first so the sheet covers the screen its result lands
  /// on, and the sheet is asked for with the navigator's overlay: it outlives
  /// this route and is still inside the navigator, which is where the sheet has
  /// to be pushed.
  Future<T?> _overShell<T>(Future<T?> Function(BuildContext shell) show) {
    final navigator = _navigator;
    navigator.popUntil((route) => route.isFirst);
    widget.demo.tabs.value = 0;
    return show(navigator.overlay?.context ?? navigator.context);
  }

  Future<void> _pickMood() async {
    final viewModel = _viewModel;
    // Captured before the panel closes: after the pop this page can no longer
    // look anything up, but its messenger outlives it.
    final messenger = ScaffoldMessenger.of(context);
    final mood = await _overShell<Mood>(
      (shell) => showMoodPicker(
        shell,
        current: viewModel.myHima?.mood ?? viewModel.lastMood,
      ),
    );
    if (mood == null) return;
    if (await applyMoodPick(viewModel, mood)) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('変更できなかった。もう一度試してね')),
    );
  }

  Future<void> _pickDuration() async {
    final viewModel = _viewModel;
    final messenger = ScaffoldMessenger.of(context);
    final minutes = await _overShell<int>(
      (shell) => showDurationPicker(
        shell,
        current: viewModel.myHima?.durationMin ?? viewModel.selectedDurationMin,
      ),
    );
    if (minutes == null) return;
    if (await applyDurationPick(viewModel, minutes)) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('変更できなかった。もう一度試してね')),
    );
  }

  Future<void> _pickActivity() async {
    final viewModel = _viewModel;
    final messenger = ScaffoldMessenger.of(context);
    final choice = await _overShell<ActivityChoice>(
      (shell) => showActivityPicker(shell, current: viewModel.selectedActivity),
    );
    if (choice == null) return;
    if (await applyActivityPick(viewModel, choice.activity)) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('変更できなかった。もう一度試してね')),
    );
  }

  Future<void> _knock() async {
    final viewModel = _viewModel;
    final messenger = ScaffoldMessenger.of(context);
    if (viewModel.friends.isEmpty) {
      // さそう needs someone hima, so the default set is staged first: the item
      // has to work from 「ひまな友達なし」 too.
      _api.setFriends(MockFriends.defaults);
      await viewModel.reloadAll();
    }
    final friends = viewModel.friends;
    if (friends.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('ひまな友達がいないよ')));
      return;
    }
    final friend = friends.first;
    await _overShell<void>(
      (shell) => showKnockSheet(
        shell,
        user: friend.user,
        activity: friend.activity,
        mood: friend.mood,
      ),
    );
  }

  /// Applies a change to the mock and re-reads through the app's own path, so
  /// the screens behind the panel show it.
  Future<void> _stage(VoidCallback change) async {
    change();
    await _viewModel.reloadAll();
    if (mounted) setState(() {});
  }

  void _setOverride(VoidCallback change) {
    setState(change);
    // The card reads the bridge through the controller, so the override has to
    // reach it before the screen is opened again.
    unawaited(_suggest.load());
  }

  Future<void> _postSuggestion(DemoSuggestionKind kind) async {
    final owner = context.read<SessionOwner>();
    final viewModel = _viewModel;
    final messenger = ScaffoldMessenger.of(context);
    // The suggestion's tap opens the declaration flow, and the app ignores it
    // while a declaration is live: ending it is what makes the posted
    // notification behave like a real one.
    if (viewModel.isDeclared) {
      try {
        await viewModel.endHima();
      } catch (_) {
        // The tap would be consumed with the declaration still live and do
        // nothing, so the failure is reported instead of posting a notification
        // that cannot work.
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('終了できなかった。もう一度試してね')),
          );
        }
        return;
      }
    }
    // The step above takes seconds in slow mode and the demo can be left while
    // it runs: the owner answers null then and posts nothing, so no demo
    // notification can appear after the demo is over.
    final posted = await owner.postDemoSuggestion(
      kind: kind,
      label: kind == DemoSuggestionKind.app ? 'YouTube' : null,
    );
    if (posted != false || !mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: const Text('通知が許可されていないよ'),
        action: SnackBarAction(
          label: '許可',
          onPressed: () => unawaited(_allowNotifications()),
        ),
      ),
    );
  }

  Future<void> _allowNotifications() async {
    try {
      await _suggest.requestNotificationPermission();
    } catch (_) {
      // The row that asked stays, so it can be pressed again.
    }
    if (mounted) setState(() {});
  }

  Future<void> _endDemo() => context.read<SessionOwner>().exitDemo();

  @override
  Widget build(BuildContext context) {
    final api = _api;
    final bridge = _bridge;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        // The same brush stroke as the other pushed screens, so the toolbar has
        // to grow with the text scale or the stroke is clipped.
        toolbarHeight: BrushTitle.toolbarHeight(context),
        title: const BrushTitle(title: 'デモ', seed: 57),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          0,
          AppSpacing.s16,
          AppSpacing.s32,
        ),
        children: [
          _section('画面', [
            _row('ホーム', () => _selectTab(0)),
            _row('友達', () => _selectTab(1)),
            _row('プロフィール', () => _selectTab(2)),
            _row(
              'お返事（届いた）',
              () => _push((_) => const KnocksScreen()),
            ),
            _row(
              'お返事（送った）',
              () => _push((_) => const KnocksScreen(showSentFirst: true)),
            ),
            _row('設定', () => _push((_) => const SettingsScreen())),
            _row('ログイン', _openLogin),
          ]),
          _section('シート', [
            _row('温度感', _pickMood),
            _row('ひまの長さ', _pickDuration),
            _row('なにする？', _pickActivity),
            _row('さそう', _knock),
          ]),
          _section('状態', [
            _row(
              '未宣言',
              () => _stage(() => api.setDeclaration(MockDeclaration.none)),
            ),
            _row(
              '宣言中',
              () => _stage(() => api.setDeclaration(MockDeclaration.live)),
            ),
            _row(
              'もうすぐ終わる',
              () => _stage(
                () => api.setDeclaration(MockDeclaration.endingSoon),
              ),
            ),
            _row(
              'ひまな友達なし',
              () => _stage(() => api.setFriends(MockFriends.none)),
            ),
            _row(
              '友達が多い',
              () => _stage(() => api.setFriends(MockFriends.many)),
            ),
            _row('お返事が届く', () => _stage(api.pushIncomingKnock)),
            _row('友達がひま宣言', () => _stage(api.friendDeclaresHima)),
            _row('マッチ成立', () => _stage(api.triggerMatch)),
            _switchRow(
              '通信エラー',
              api.failEveryCall,
              (value) {
                setState(() => api.failEveryCall = value);
                // The switch is the state being shown, so the app's own error
                // state has to appear on the screens behind the panel.
                unawaited(_viewModel.reloadAll());
              },
            ),
            _switchRow(
              '遅い通信',
              api.slowEveryCall,
              // Nothing to reload: the next call the app makes pays it.
              (value) => setState(() => api.slowEveryCall = value),
            ),
            _row('最初に戻す', () => _stage(api.reset)),
          ]),
          _section('自動ひま提案', [
            _row(
              '「アプリ利用中」の通知',
              () => _postSuggestion(DemoSuggestionKind.app),
            ),
            _row(
              '「いつもの時間」の通知',
              () => _postSuggestion(DemoSuggestionKind.usual),
            ),
            _switchRow(
              '使用状況の許可なし',
              bridge.usageAccessMissing,
              (value) => _setOverride(() => bridge.usageAccessMissing = value),
            ),
            _switchRow(
              '通知の許可なし',
              bridge.notificationsMissing,
              (value) =>
                  _setOverride(() => bridge.notificationsMissing = value),
            ),
          ]),
          const SizedBox(height: AppSpacing.s32),
          PaintButton(
            seed: 993,
            label: 'デモを終える',
            icon: Icons.close_rounded,
            color: AppColors.purple,
            foreground: AppColors.surface,
            minHeight: 56,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s24,
              vertical: AppSpacing.s16,
            ),
            textStyle: AppTextStyles.button.copyWith(fontSize: 17),
            onPressed: _endDemo,
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s24,
          AppSpacing.s4,
          AppSpacing.s8,
        ),
        child: Text(
          title,
          maxLines: 2,
          style: AppTextStyles.friendName.copyWith(fontSize: 17),
        ),
      ),
      PaintWash(
        seed: paintSeedOf('demo-$title'),
        color: AppColors.purpleSoft,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s8,
        ),
        corner: AppSpacing.radiusCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ],
  );

  Widget _row(String label, VoidCallback onTap) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );
}
