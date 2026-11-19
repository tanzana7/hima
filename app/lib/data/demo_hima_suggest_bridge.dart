import 'package:flutter/foundation.dart';

import 'hima_suggest_bridge.dart';
import 'models/models.dart';

/// The demo session's view of 「自動ひま提案」.
///
/// The worker's state lives in the phone (its own shared preferences), so the
/// demo keeps a copy of everything it could write in memory instead: the
/// settings card, the target list and the declaration mirror all behave as on a
/// device without touching the state the real session reads.
///
/// Permission status is the exception. It describes the phone rather than the
/// account, so it comes from [HimaSuggestBridge.getState] of the real bridge,
/// with two switches the demo panel can turn on to force the permission rows
/// to appear.
class DemoHimaSuggestBridge implements HimaSuggestBridge {
  DemoHimaSuggestBridge(this._real)
    : _targets = [for (final app in himaSuggestTemplates) app.package];

  final HimaSuggestBridge _real;

  bool _enabled = false;
  List<String> _targets;
  int _appTriggerMinutes = himaSuggestDefaultTriggerMinutes;
  DateTime? _declaredUntil;
  List<HimaTimeSuggestion> _forecast = const [];
  VoidCallback? _onAction;

  /// True while the panel reports the usage access as missing, so the
  /// 「使用状況へのアクセス」 row can be shown on a phone that already granted it.
  bool usageAccessMissing = false;

  /// True while the panel reports notifications as not allowed, for the same
  /// reason.
  bool notificationsMissing = false;

  /// One stable closure, because the real bridge's handler slot is compared by
  /// identity when this bridge (or a shell that is being disposed) asks to
  /// clear it.
  late final VoidCallback _forward = _forwardAction;

  void _forwardAction() => _onAction?.call();

  /// The declaration mirror the demo view model last published, kept so the
  /// demo never asks the phone for it.
  DateTime? get declaredUntil => _declaredUntil;

  /// The usual times the demo view model last published.
  List<HimaTimeSuggestion> get forecast => _forecast;

  /// The worker exists in the demo, so the card stays visible even where the
  /// real bridge is a no-op.
  @override
  bool get isSupported => true;

  @override
  VoidCallback? get onAction => _onAction;

  @override
  set onAction(VoidCallback? value) {
    _onAction = value;
    if (value == null) {
      // Two trees overlap while the session is swapped: the new shell registers
      // before the old one is disposed. A null from the tree that is leaving
      // must not silence the owner that already took the slot, so the slot is
      // only cleared while this bridge still holds it.
      if (identical(_real.onAction, _forward)) _real.onAction = null;
      return;
    }
    _real.onAction = _forward;
  }

  @override
  Future<HimaSuggestState> getState() async {
    final real = await _realState();
    // Labels and the installed flag describe the phone, so they still come from
    // the real bridge; only what the demo owns is replaced.
    final known = {
      for (final target in real.targets) target.package: target,
    };
    return HimaSuggestState(
      enabled: _enabled,
      targets: List.unmodifiable([
        for (final package in _targets)
          HimaSuggestTarget(
            package: package,
            label: known[package]?.label ?? _templateLabel(package),
            // A package only the demo knows cannot be looked up on the device,
            // and a row that reads 未インストール for a demo-only entry would be
            // noise rather than a fact.
            installed: known[package]?.installed ?? true,
          ),
      ]),
      usageAccess: real.usageAccess && !usageAccessMissing,
      notificationsAllowed: real.notificationsAllowed && !notificationsMissing,
      appTriggerMinutes: _appTriggerMinutes,
    );
  }

  /// A failed read must not blank the demo card: the phone facts are the part
  /// that can be unavailable, and everything the demo owns is still answerable.
  Future<HimaSuggestState> _realState() async {
    try {
      return await _real.getState();
    } catch (_) {
      return HimaSuggestState.disabled;
    }
  }

  static String _templateLabel(String package) {
    for (final app in himaSuggestTemplates) {
      if (app.package == package) return app.label;
    }
    return package;
  }

  @override
  Future<HimaSuggestState> setEnabled(bool enabled) async {
    _enabled = enabled;
    return getState();
  }

  @override
  Future<HimaSuggestState> setTargets(List<String> packages) async {
    // Order is the user's, like the native store: duplicates would only make
    // the list ambiguous.
    _targets = List.unmodifiable(packages.toSet());
    return getState();
  }

  /// Kept in memory like the targets, so trying the choice in the demo cannot
  /// change how the phone's real suggestions behave.
  @override
  Future<HimaSuggestState> setAppTriggerMinutes(int minutes) async {
    _appTriggerMinutes = minutes;
    return getState();
  }

  @override
  Future<List<HimaSuggestApp>> listLaunchableApps() =>
      _real.listLaunchableApps();

  @override
  Future<void> openUsageAccessSettings() => _real.openUsageAccessSettings();

  /// Asks the real bridge, and drops the demo override when the permission was
  /// granted: the row the override forced to appear is what the answer is
  /// about.
  @override
  Future<bool> requestNotificationPermission() async {
    final granted = await _real.requestNotificationPermission();
    if (granted) notificationsMissing = false;
    return granted;
  }

  /// Kept in memory only. The worker decides what to suggest from the real
  /// state, and a demo must not silence a real suggestion.
  @override
  Future<void> setDeclaredUntil(DateTime? expiresAt) async {
    _declaredUntil = expiresAt;
  }

  @override
  Future<void> setForecast(List<HimaTimeSuggestion> forecast) async {
    _forecast = List.unmodifiable(forecast);
  }

  /// The demo logout: only the memory cleared above.
  @override
  Future<void> clear() async {
    _enabled = false;
    _targets = [for (final app in himaSuggestTemplates) app.package];
    _appTriggerMinutes = himaSuggestDefaultTriggerMinutes;
    _declaredUntil = null;
    _forecast = const [];
  }

  /// Reads the real slot and hands a demo action to the shell as the real one.
  ///
  /// A real `declare` taken while the demo is on screen belongs to the account
  /// that is not being shown, so it is dropped. The read consumes it either
  /// way, which is an accepted edge of a developer tool. Both demo actions are
  /// mapped to their real counterparts for the same reason the notification
  /// reuses the real bodies: the demo has to behave like the real thing, and
  /// what keeps that safe is the demo-only token the notification carries.
  @override
  Future<String?> takePendingAction() async {
    final action = await _real.takePendingAction();
    return switch (action) {
      himaSuggestDemoDeclareAction => himaSuggestDeclareAction,
      himaSuggestDemoDeclareNowAction => himaSuggestDeclareNowAction,
      _ => null,
    };
  }

  @override
  Future<bool> postDemoSuggestion({
    required DemoSuggestionKind kind,
    String? label,
    bool marked = true,
    int delayMs = 0,
  }) => _real.postDemoSuggestion(
    kind: kind,
    label: label,
    marked: marked,
    delayMs: delayMs,
  );

  @override
  Future<void> cancelDemoSuggestion() => _real.cancelDemoSuggestion();
}
