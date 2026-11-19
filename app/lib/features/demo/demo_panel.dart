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

  /// How long the 「10秒後に出す」 switch makes the notification wait: enough time
  /// to leave the app for YouTube and start recording the moment it arrives.
  static const _suggestionDelay = Duration(seconds: 10);

  /// True while the notification rows schedule their post instead of posting it
  /// now, so the app can be left before the notification appears.
  bool _delayedSuggestion = false;

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
    messenger.showSnackBar(const SnackBar(content: Text('変更できなかった。もう一度試してね')));
  }

  void _openHomePicker(DemoHomePickerKind kind) {
    widget.demo.homePickerRequest.value = DemoHomePickerRequest(kind);
    _selectTab(0);
  }

  void _pickDuration() => _openHomePicker(DemoHomePickerKind.duration);

  void _pickActivity() => _openHomePicker(DemoHomePickerKind.activity);

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

  /// Applies a change to the mock, returns to the home tab and re-reads through
  /// the app's own path.
  ///
  /// The panel closes because these rows change nothing on the panel itself:
  /// staying open made a tap look like it did nothing. It closes before the
  /// read so the tap answers at once even in slow mode.
  Future<void> _stage(VoidCallback change) async {
    // Captured first: the page can no longer look it up once it is popped.
    final viewModel = _viewModel;
    change();
    _selectTab(0);
    await viewModel.reloadAll();
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
    final delayMs = _delayedSuggestion ? _suggestionDelay.inMilliseconds : 0;
    final label = kind == DemoSuggestionKind.app ? 'YouTube' : null;
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
    // Read after the step above, not before: 撮影モード can be turned on while a
    // declaration is being ended, and the notification has to look real then.
    final marked = !widget.demo.captureMode.value;
    // The step above takes seconds in slow mode and the demo can be left while
    // it runs: the owner answers null then and posts nothing, so no demo
    // notification can appear after the demo is over.
    final posted = await owner.postDemoSuggestion(
      kind: kind,
      label: label,
      marked: marked,
      delayMs: delayMs,
    );
    if (!mounted) return;
    if (posted != true) {
      if (posted == false) {
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
      return;
    }
    if (delayMs == 0) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('10秒後に通知するよ'),
        duration: Duration(seconds: 2),
      ),
    );
    // While recording is being set up the next step is leaving for YouTube, and
    // the ten seconds are already running.
    if (!marked) _selectTab(0);
  }

  /// Turns 撮影モード on or off.
  ///
  /// The panel stays open: the notification for the recording is requested from
  /// here, and the 「デモ」 subtext is decided when it is requested. The floating
  /// button stops appearing as soon as the panel closes (`DemoOverlay`), and the
  /// long press in the top-left corner is the way back.
  void _setCaptureMode(bool value) {
    setState(() => widget.demo.captureMode.value = value);
  }

  /// Shows the app's own error state on the home tab.
  ///
  /// The home screen only had an error UI when the list was empty, so turning
  /// the failure on alone looked like it did nothing: the friends it had already
  /// read stayed on screen. An empty board is staged and read successfully
  /// first, then the failure is turned on and read again, so the error UI the
  /// app already has is what the home tab ends up showing.
  Future<void> _toggleFailures(bool value) async {
    final api = _api;
    final viewModel = _viewModel;
    // Captured before the panel closes, which happens before both reads.
    _selectTab(0);
    if (!value) {
      api.failEveryCall = false;
      api.setFriends(MockFriends.defaults);
      await viewModel.reloadAll();
      return;
    }
    api
      ..failEveryCall = false
      ..setFriends(MockFriends.none);
    await viewModel.reloadAll();
    // Only now: with the failure on, the read above could not have staged the
    // empty list in the first place.
    api.failEveryCall = true;
    await viewModel.reloadAll();
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
          _section('撮影', [
            _switchRow('撮影モード', widget.demo.captureMode.value, _setCaptureMode),
          ]),
          _section('画面', [
            _row('ホーム', () => _selectTab(0)),
            _row('友達', () => _selectTab(1)),
            _row('プロフィール', () => _selectTab(2)),
            _row('お返事（届いた）', () => _push((_) => const KnocksScreen())),
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
              () =>
                  _stage(() => api.setDeclaration(MockDeclaration.endingSoon)),
            ),
            _row(
              'ひまな友達なし',
              () => _stage(() => api.setFriends(MockFriends.none)),
            ),
            _row('友達が多い', () => _stage(() => api.setFriends(MockFriends.many))),
            _row('お返事が届く', () => _stage(api.pushIncomingKnock)),
            _row('友達がひま宣言', () => _stage(api.friendDeclaresHima)),
            _row('マッチ成立', () => _stage(api.triggerMatch)),
            _switchRow(
              '通信エラー',
              api.failEveryCall,
              (value) => unawaited(_toggleFailures(value)),
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
            _switchRow(
              '10秒後に出す',
              _delayedSuggestion,
              (value) => setState(() => _delayedSuggestion = value),
            ),
            _row('「アプリ利用中」の通知', () => _postSuggestion(DemoSuggestionKind.app)),
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
