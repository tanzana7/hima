// Temporary manual check for the native 自動ひま提案 channel. Deleted before hand-off.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const channel = MethodChannel('jp.atsumaro.atsumaro/suggest');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = File('${Directory.systemTemp.path}/suggest_smoke.json');
  final results = <String, Object?>{};
  final actions = <Object?>[];

  Future<void> flush() async {
    results['onAction'] = actions;
    await output.writeAsString(jsonEncode(results));
  }

  Future<Object?> call(String name, [Object? args]) async {
    try {
      return await channel.invokeMethod<Object?>(name, args);
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  channel.setMethodCallHandler((MethodCall call) async {
    debugPrint('SMOKE onAction ${call.method} ${call.arguments}');
    if (call.method == 'onAction') {
      actions.add(call.arguments);
      await flush();
    }
    return null;
  });

  results['takePendingAction.cold'] = await call('takePendingAction');
  results['getState.initial'] = await call('getState');
  final apps = await call('listLaunchableApps');
  if (apps is List) {
    results['listLaunchableApps.count'] = apps.length;
    results['listLaunchableApps.first'] = apps.take(3).toList();
    results['listLaunchableApps.labels'] = apps
        .map((Object? e) => (e as Map)['label'])
        .take(10)
        .toList();
  } else {
    results['listLaunchableApps'] = apps;
  }
  results['setTargets'] = await call('setTargets', [
    'com.google.android.youtube',
    'com.android.chrome',
    'com.google.android.youtube',
  ]);
  results['setDeclaredUntil.set'] = await call('setDeclaredUntil', 1893456000000);
  results['setDeclaredUntil.clear'] = await call('setDeclaredUntil', null);
  final now = DateTime.now();
  final weekday = (now.weekday - 1) % 7;
  final minutes = now.hour * 60 + now.minute;
  results['setForecast'] = await call(
    'setForecast',
    <Map<String, Object?>>[
      {
        'weekday': weekday,
        'start_min': (minutes - 60).clamp(0, 1439),
        'end_min': (minutes + 60).clamp(0, 1440),
      },
    ],
  );
  results['requestNotificationPermission'] = await call(
    'requestNotificationPermission',
  );
  results['setEnabled.true'] = await call('setEnabled', true);
  results['getState.enabled'] = await call('getState');
  results['takePendingAction.after'] = await call('takePendingAction');
  await flush();

  results['openUsageAccessSettings'] = await call('openUsageAccessSettings');
  await flush();

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'suggest smoke\n${results['listLaunchableApps.count']} apps',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
