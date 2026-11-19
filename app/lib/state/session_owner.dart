import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/api_client.dart';
import '../data/app_config.dart';
import '../data/demo_hima_suggest_bridge.dart';
import '../data/hima_suggest_bridge.dart';
import '../data/mock_api_client.dart';
import 'app_view_model.dart';
import 'hima_suggest_controller.dart';

/// Everything one session's widgets read: the server state and the device
/// 「自動ひま提案」 state.
///
/// Not to be confused with [HimaSession], which is a hima declaration; a session
/// here is "who is signed in right now".
class AppSession {
  AppSession({required this.viewModel, required this.suggest});

  final AppViewModel viewModel;
  final HimaSuggestController suggest;
}

enum DemoHomePickerKind { activity, duration }

class DemoHomePickerRequest {
  const DemoHomePickerRequest(this.kind);

  final DemoHomePickerKind kind;
}

/// The demo session: the mock behind an [AppSession], plus what only the demo
/// panel needs.
class DemoSession extends AppSession {
  DemoSession({
    required super.viewModel,
    required super.suggest,
    required this.api,
    required this.bridge,
  });

  /// The mock every demo screen reads, and the panel edits.
  final MockApiClient api;

  /// Kept in memory, so nothing here reaches the phone's real 自動ひま提案
  /// state.
  final DemoHimaSuggestBridge bridge;

  /// The tab the shell should show. Shared so the panel can move the shell
  /// without reaching into its state, and so its own selection stays in sync.
  final ValueNotifier<int> tabs = ValueNotifier<int>(0);

  /// One-shot requests from the demo panel to open a picker inside the home
  /// hero. The real session never owns or observes this hook.
  final ValueNotifier<DemoHomePickerRequest?> homePickerRequest =
      ValueNotifier<DemoHomePickerRequest?>(null);

  /// True while the panel covers the app, so the panel's floating entry point
  /// does not sit on top of the panel itself.
  final ValueNotifier<bool> panelVisible = ValueNotifier<bool>(false);

  /// True while the owner is recording 撮影モード.
  ///
  /// Nothing developer-looking may appear on camera then, so the floating entry
  /// point disappears and the demo notifications drop their 「デモ」 subtext. It
  /// lives on this session, so it ends with it: none of it can reach the real
  /// session or the phone's notification state.
  final ValueNotifier<bool> captureMode = ValueNotifier<bool>(false);

  /// The panel's own route is pushed from above the navigator, so the demo
  /// session is the only one that needs a handle on it.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

/// Holds the real session and, while the demo is on, the demo session.
///
/// The demo cannot be a second [ApiClient] swapped into the real view model: the
/// real one owns the stored token and mirrors the live declaration into the
/// phone's worker, and neither may be touched from a developer tool. So both
/// sessions are kept as whole objects and only one of them is on screen at a
/// time.
class SessionOwner extends ChangeNotifier {
  SessionOwner({
    required this.config,
    required ApiClient api,
    required HimaSuggestBridge bridge,
  }) : _bridge = bridge,
       real = AppSession(
         viewModel: AppViewModel(api, bridge),
         suggest: HimaSuggestController(bridge),
       );

  final AppConfig config;

  /// The one bridge for the whole app: the native worker holds a single state,
  /// and the demo bridge only wraps this one.
  final HimaSuggestBridge _bridge;

  /// Never disposed and never swapped out, so the token and the signed-in state
  /// survive a demo the same way they survive a tab switch.
  final AppSession real;

  DemoSession? _demo;
  bool _entering = false;

  /// True from the moment [exitDemo] starts: a demo suggestion that is still
  /// being posted must not start another one, and the cancel comes last.
  bool _leavingDemo = false;

  /// The demo suggestion post that is still running, so [exitDemo] can wait for
  /// it before it drops the notification.
  Future<void>? _demoPost;

  /// The session the widgets below `MaterialApp` belong to.
  AppSession get active => _demo ?? real;

  /// The demo session while it is on, null otherwise.
  DemoSession? get demo => _demo;

  bool get isDemo => _demo != null;

  /// Debug and profile builds, and mock builds even in release: nothing of the
  /// demo is reachable from a release build that talks to the server.
  bool get canUseDemo => !kReleaseMode || config.useMockApi;

  /// True where an entry point into the demo may be shown: allowed by the build
  /// and not already inside the demo.
  bool get showDemoEntry => canUseDemo && !isDemo;

  /// Restores the token saved by a previous launch. Called once at startup; the
  /// demo never asks for it again.
  Future<void> restore() => real.viewModel.restoreSession();

  /// Posts one of the demo notifications, while the demo is on screen.
  ///
  /// Answers whether the platform took it, or null when the demo ended before
  /// the post could run: the panel asks for this after a step that takes seconds
  /// in slow mode, and a notification posted afterwards would outlive the demo.
  /// The post is recorded so [exitDemo] can wait for it, which is what keeps the
  /// cancel it does the last word on the notification — a delayed post that has
  /// only been scheduled is dropped by the same cancel.
  Future<bool?> postDemoSuggestion({
    required DemoSuggestionKind kind,
    String? label,
    bool marked = true,
    int delayMs = 0,
  }) async {
    final session = _demo;
    if (session == null || _leavingDemo) return null;
    final post = session.bridge.postDemoSuggestion(
      kind: kind,
      label: label,
      marked: marked,
      delayMs: delayMs,
    );
    // Tracked separately so exiting can wait for it without the tracked copy
    // itself failing when the channel does.
    final tracked = post.then<void>((_) {}, onError: (Object _) {});
    _demoPost = tracked;
    try {
      return await post;
    } catch (_) {
      // A channel that cannot post answers like a denied permission.
      return false;
    } finally {
      if (identical(_demoPost, tracked)) _demoPost = null;
    }
  }

  /// Swaps the screen to the demo session.
  ///
  /// The real view model keeps its objects, its state and its token: its polling
  /// is stopped and everything it can still be doing to the outside world is
  /// held, so leaving the demo puts back the same screen without a
  /// `restoreSession()`.
  Future<void> enterDemo() async {
    // `_entering` covers a second tap while the mock login below is awaited, so
    // two demo sessions cannot be built for one entry point.
    if (_demo != null || _entering || !canUseDemo) return;
    _entering = true;
    try {
      real.viewModel.stopPolling();
      // Stopping the polling only cancels the timer: a refresh that is already
      // in flight still lands afterwards. The whole session is held here, before
      // anything of the demo exists, so neither the worker's state nor the
      // stored token can change while the demo is on screen (a read that answers
      // 401, or a startup restore that finishes late, is left for the first
      // request after the demo).
      real.viewModel.holdForDemo();
      final api = MockApiClient();
      final bridge = DemoHimaSuggestBridge(_bridge);
      final viewModel = AppViewModel(api, bridge);
      final session = DemoSession(
        viewModel: viewModel,
        suggest: HimaSuggestController(bridge),
        api: api,
        bridge: bridge,
      );
      try {
        // The mock login is what makes the demo shell reachable without Discord.
        // Nothing here can reach HttpApiClient, so no request leaves the device.
        await viewModel.loginAsDemo();
      } catch (_) {
        // The mock only fails when the panel asks it to, so this cannot happen
        // on entry; going back to the real session is still safer than showing
        // a shell that cannot load. The real session is back on screen, so it
        // has to act again.
        real.viewModel.releaseAfterDemo();
        real.viewModel.startPolling();
        return;
      }
      _leavingDemo = false;
      _demo = session;
      notifyListeners();
    } finally {
      _entering = false;
    }
  }

  /// Drops the demo session and shows the real one exactly as it was left.
  Future<void> exitDemo() async {
    final session = _demo;
    if (session == null) return;
    // No new post from here on: the ones below are waited for so the cancel has
    // the last word.
    _leavingDemo = true;
    session.viewModel.stopPolling();
    final post = _demoPost;
    if (post != null) await post;
    try {
      // A demo notification left in the shade would otherwise still be tappable
      // after the demo is over; this drops it and invalidates its token.
      await _bridge.cancelDemoSuggestion();
    } catch (_) {
      // The notification is a convenience: the session still has to end.
    }
    _demo = null;
    // Before the tree is rebuilt: the poll that the real shell starts again
    // mirrors the unchanged state of the real session, which is wanted once the
    // demo is over.
    real.viewModel.releaseAfterDemo();
    notifyListeners();
    // The demo view model is deliberately not disposed: a knock sent just before
    // leaving has a delayed read queued on it, and that read would notify a
    // disposed object. Nothing can reach it once the tree is rebuilt.
    // `startPolling` decides from the session itself, which may have been signed
    // in by the restore that was still running when the demo started.
    real.viewModel.startPolling();
  }
}
