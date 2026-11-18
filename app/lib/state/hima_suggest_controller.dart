import 'package:flutter/foundation.dart';

import '../data/hima_suggest_bridge.dart';

/// The device state of 「自動ひま提案」, shared by the settings section and the
/// app shell.
///
/// It is kept out of [AppViewModel] because this is device state rather than
/// server state: the worker lives in Android, and `/app/me` cannot describe it.
class HimaSuggestController extends ChangeNotifier {
  HimaSuggestController(this._bridge);

  final HimaSuggestBridge _bridge;

  HimaSuggestState _state = HimaSuggestState.disabled;

  /// True only where the native worker exists, so the settings section can be
  /// hidden without a channel round trip.
  bool get isSupported => _bridge.isSupported;

  bool get enabled => _state.enabled;
  List<HimaSuggestTarget> get targets => _state.targets;
  bool get usageAccess => _state.usageAccess;
  bool get notificationsAllowed => _state.notificationsAllowed;

  /// A tapped notification while the app is running.
  VoidCallback? get onAction => _bridge.onAction;
  set onAction(VoidCallback? value) => _bridge.onAction = value;

  /// Reads the state from the device.
  ///
  /// A failed read keeps what is already shown: this runs on every resume, and
  /// a one-off error must not blank the section or raise a snackbar the user
  /// did not ask for.
  Future<void> load() async {
    if (!_bridge.isSupported) return;
    try {
      _apply(await _bridge.getState());
    } catch (_) {
      // Keep the last known state; the next resume or action retries.
    }
  }

  Future<void> setEnabled(bool value) async {
    _apply(await _bridge.setEnabled(value));
  }

  Future<void> setTargets(List<String> packages) async {
    _apply(await _bridge.setTargets(packages));
  }

  Future<List<HimaSuggestApp>> listLaunchableApps() =>
      _bridge.listLaunchableApps();

  Future<void> openUsageAccessSettings() => _bridge.openUsageAccessSettings();

  /// Asks for the notification permission and mirrors the answer, so the
  /// 「通知」 row disappears without another round trip.
  Future<bool> requestNotificationPermission() async {
    final granted = await _bridge.requestNotificationPermission();
    if (granted != _state.notificationsAllowed) {
      _apply(_state.copyWith(notificationsAllowed: granted));
    }
    return granted;
  }

  Future<String?> takePendingAction() => _bridge.takePendingAction();

  void _apply(HimaSuggestState state) {
    _state = state;
    notifyListeners();
  }
}
