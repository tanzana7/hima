import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/api_client.dart';
import 'data/app_config.dart';
import 'data/hima_suggest_bridge.dart';
import 'data/http_api_client.dart';
import 'data/mock_api_client.dart';
import 'state/session_owner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig.fromEnvironment;
  // No API_BASE_URL means the offline demo: the mock answers every call, which
  // is how the app runs without a server.
  final ApiClient api = config.useMockApi
      ? MockApiClient()
      : HttpApiClient(baseUrl: config.apiBaseUrl);
  // One bridge for the whole app: the native worker holds a single state, so a
  // second instance would answer with a second, diverging copy of it.
  final suggestBridge = createHimaSuggestBridge();
  // The owner holds the real session (and, once entered, the demo one); it is
  // created here so the real view model exists before the first frame, and it
  // outlives every rebuild of the widget tree.
  final sessions = SessionOwner(
    config: config,
    api: api,
    bridge: suggestBridge,
  );
  // A token saved by a previous launch is restored in the background; the login
  // screen stays up until /app/me accepts it.
  unawaited(sessions.restore());
  runApp(HimaApp(config: config, sessions: sessions));
}
