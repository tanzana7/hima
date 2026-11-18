import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/models.dart';

/// One app the native suggestion worker watches for use.
@immutable
class HimaSuggestTarget {
  const HimaSuggestTarget({
    required this.package,
    required this.label,
    required this.installed,
  });

  final String package;

  /// Name shown to the user; the Android launcher label.
  final String label;

  /// False when the app is no longer on the device. The row stays listed so the
  /// user can still remove it, but the worker cannot watch it.
  final bool installed;
}

/// An app the user can add as a target, from `listLaunchableApps`.
@immutable
class HimaSuggestApp {
  const HimaSuggestApp({required this.package, required this.label});

  final String package;
  final String label;
}

/// The apps the native side starts with, in display order.
///
/// They are kept here too because removing one has to be undoable: the add
/// sheet offers them again even when the app is not installed, which is why
/// they cannot come from `listLaunchableApps`.
const List<HimaSuggestApp> himaSuggestTemplates = [
  HimaSuggestApp(package: 'com.twitter.android', label: 'X'),
  HimaSuggestApp(package: 'com.google.android.youtube', label: 'YouTube'),
];

/// The device state of 「自動ひま提案」.
///
/// The values are read from the device, not from `/app/me`: the feature only
/// exists on Android, so a server flag could not describe it.
@immutable
class HimaSuggestState {
  const HimaSuggestState({
    this.enabled = false,
    this.targets = const [],
    this.usageAccess = false,
    this.notificationsAllowed = false,
  });

  /// The empty state: nothing enabled and no permission granted.
  static const disabled = HimaSuggestState();

  final bool enabled;
  final List<HimaSuggestTarget> targets;
  final bool usageAccess;
  final bool notificationsAllowed;

  HimaSuggestState copyWith({bool? notificationsAllowed}) => HimaSuggestState(
    enabled: enabled,
    targets: targets,
    usageAccess: usageAccess,
    notificationsAllowed: notificationsAllowed ?? this.notificationsAllowed,
  );
}

/// The Dart half of the native 「自動ひま提案」 worker.
///
/// The worker itself (Android only) posts a local notification when the user is
/// in a target app or near a time they are usually free. It never declares on
/// its own: this side only mirrors the state the settings screen shows and the
/// facts the worker needs to decide when to suggest.
abstract interface class HimaSuggestBridge {
  /// True only where the worker exists. The settings section is hidden where it
  /// is false, so no other call has to be attempted there.
  bool get isSupported;

  /// Called when a suggestion notification is tapped while the app is running.
  ///
  /// The action is stored natively as well, so a handler reacts by reading
  /// [takePendingAction] instead of trusting this signal alone.
  VoidCallback? get onAction;
  set onAction(VoidCallback? value);

  Future<HimaSuggestState> getState();
  Future<HimaSuggestState> setEnabled(bool enabled);

  /// Packages in display order. Answers with the state after the write.
  Future<HimaSuggestState> setTargets(List<String> packages);

  /// Launchable apps on the device, by label, without this app.
  Future<List<HimaSuggestApp>> listLaunchableApps();

  Future<void> openUsageAccessSettings();

  /// Answers whether notifications are allowed afterwards.
  Future<bool> requestNotificationPermission();

  /// Epoch time the live declaration expires at, or null when not declared.
  Future<void> setDeclaredUntil(DateTime? expiresAt);

  /// The times the worker may suggest, as `GET /app/free-time/forecast`
  /// returns them (weekday 0 = Monday, minutes from midnight in Asia/Tokyo).
  Future<void> setForecast(List<HimaTimeSuggestion> forecast);

  /// Logout: disables the worker, drops the notification and the user's caches.
  Future<void> clear();

  /// `"declare"` when the app was opened from a suggestion and the action has
  /// not been taken yet. Consumed once, so a second call returns null.
  Future<String?> takePendingAction();
}

/// The value [takePendingAction] answers for a tapped notification.
const String himaSuggestDeclareAction = 'declare';

/// The bridge this platform can use: the channel on Android, a no-op anywhere
/// else (including widget-only contexts, which have no plugin registry).
HimaSuggestBridge createHimaSuggestBridge() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? MethodChannelHimaSuggestBridge()
    : const NoopHimaSuggestBridge();

/// Talks to the Kotlin worker over `jp.atsumaro.atsumaro/suggest`.
class MethodChannelHimaSuggestBridge implements HimaSuggestBridge {
  MethodChannelHimaSuggestBridge({MethodChannel channel = _defaultChannel})
    : _channel = channel;

  static const _defaultChannel = MethodChannel('jp.atsumaro.atsumaro/suggest');

  static const _methodGetState = 'getState';
  static const _methodSetEnabled = 'setEnabled';
  static const _methodSetTargets = 'setTargets';
  static const _methodListLaunchableApps = 'listLaunchableApps';
  static const _methodOpenUsageAccessSettings = 'openUsageAccessSettings';
  static const _methodRequestNotificationPermission =
      'requestNotificationPermission';
  static const _methodSetDeclaredUntil = 'setDeclaredUntil';
  static const _methodSetForecast = 'setForecast';
  static const _methodClear = 'clear';
  static const _methodTakePendingAction = 'takePendingAction';
  static const _methodOnAction = 'onAction';

  final MethodChannel _channel;
  VoidCallback? _onAction;

  @override
  bool get isSupported => true;

  @override
  VoidCallback? get onAction => _onAction;

  @override
  set onAction(VoidCallback? value) {
    _onAction = value;
    // Installed only while somebody listens: the handler outlives the widget
    // tree otherwise, and the listener would be called from a dead state object.
    _channel.setMethodCallHandler(value == null ? null : _handleCall);
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == _methodOnAction &&
        _actionOf(call.arguments) == himaSuggestDeclareAction) {
      _onAction?.call();
    }
    return null;
  }

  @override
  Future<HimaSuggestState> getState() async =>
      _readState(await _channel.invokeMethod<Object?>(_methodGetState));

  @override
  Future<HimaSuggestState> setEnabled(bool enabled) async => _readState(
    await _channel.invokeMethod<Object?>(_methodSetEnabled, enabled),
  );

  @override
  Future<HimaSuggestState> setTargets(List<String> packages) async =>
      _readState(
        await _channel.invokeMethod<Object?>(_methodSetTargets, packages),
      );

  @override
  Future<List<HimaSuggestApp>> listLaunchableApps() async {
    final value = await _channel.invokeMethod<Object?>(
      _methodListLaunchableApps,
    );
    if (value is! List) return const [];
    final apps = <HimaSuggestApp>[];
    for (final item in value) {
      if (item is! Map) continue;
      final package = item['package'];
      if (package is! String || package.isEmpty) continue;
      apps.add(HimaSuggestApp(package: package, label: _labelOf(item, package)));
    }
    return apps;
  }

  @override
  Future<void> openUsageAccessSettings() async {
    await _channel.invokeMethod<Object?>(_methodOpenUsageAccessSettings);
  }

  @override
  Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>(_methodRequestNotificationPermission) ??
      false;

  @override
  Future<void> setDeclaredUntil(DateTime? expiresAt) async {
    await _channel.invokeMethod<Object?>(
      _methodSetDeclaredUntil,
      expiresAt?.millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> setForecast(List<HimaTimeSuggestion> forecast) async {
    await _channel.invokeMethod<Object?>(_methodSetForecast, [
      for (final slot in forecast)
        {
          'weekday': slot.weekday,
          'start_min': slot.startMin,
          'end_min': slot.endMin,
        },
    ]);
  }

  @override
  Future<void> clear() async {
    await _channel.invokeMethod<Object?>(_methodClear);
  }

  @override
  Future<String?> takePendingAction() async {
    final value = await _channel.invokeMethod<Object?>(
      _methodTakePendingAction,
    );
    return value is String ? value : null;
  }

  /// `onAction("declare")`. A map is accepted too so a richer payload added
  /// later does not need a matching change here.
  static String? _actionOf(Object? arguments) {
    if (arguments is String) return arguments;
    if (arguments is Map) {
      final action = arguments['action'];
      if (action is String) return action;
    }
    return null;
  }

  static String _labelOf(Map<Object?, Object?> json, String package) {
    final label = json['label'];
    // A missing label still has to identify the row well enough to remove it.
    return label is String && label.isNotEmpty ? label : package;
  }

  /// Reads the map every state-returning method answers with.
  ///
  /// A malformed field falls back to "nothing enabled" instead of throwing:
  /// this runs on every settings screen build, and one unexpected value must
  /// not break the whole screen.
  static HimaSuggestState _readState(Object? value) {
    if (value is! Map) return HimaSuggestState.disabled;
    final targets = <HimaSuggestTarget>[];
    final rawTargets = value['targets'];
    if (rawTargets is List) {
      for (final item in rawTargets) {
        if (item is! Map) continue;
        final package = item['package'];
        if (package is! String || package.isEmpty) continue;
        targets.add(
          HimaSuggestTarget(
            package: package,
            label: _labelOf(item, package),
            installed: item['installed'] == true,
          ),
        );
      }
    }
    return HimaSuggestState(
      enabled: value['enabled'] == true,
      targets: List.unmodifiable(targets),
      usageAccess: value['usageAccess'] == true,
      notificationsAllowed: value['notificationsAllowed'] == true,
    );
  }
}

/// The stand-in for every platform without the worker, and for widget-only
/// contexts.
///
/// Calls answer with the empty, disabled state rather than throwing, so a
/// caller that ignores [isSupported] still cannot show a switch that would
/// change nothing.
class NoopHimaSuggestBridge implements HimaSuggestBridge {
  const NoopHimaSuggestBridge();

  @override
  bool get isSupported => false;

  @override
  VoidCallback? get onAction => null;

  @override
  set onAction(VoidCallback? value) {}

  @override
  Future<HimaSuggestState> getState() async => HimaSuggestState.disabled;

  @override
  Future<HimaSuggestState> setEnabled(bool enabled) async =>
      HimaSuggestState.disabled;

  @override
  Future<HimaSuggestState> setTargets(List<String> packages) async =>
      HimaSuggestState.disabled;

  @override
  Future<List<HimaSuggestApp>> listLaunchableApps() async => const [];

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<void> setDeclaredUntil(DateTime? expiresAt) async {}

  @override
  Future<void> setForecast(List<HimaTimeSuggestion> forecast) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<String?> takePendingAction() async => null;
}
