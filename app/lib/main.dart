import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'data/api_client.dart';
import 'data/app_config.dart';
import 'data/hima_suggest_bridge.dart';
import 'data/http_api_client.dart';
import 'data/mock_api_client.dart';
import 'state/app_view_model.dart';
import 'state/hima_suggest_controller.dart';

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
  final viewModel = AppViewModel(api, suggestBridge);
  // A token saved by a previous launch is restored in the background; the login
  // screen stays up until /app/me accepts it.
  unawaited(viewModel.restoreSession());
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppViewModel>.value(value: viewModel),
        ChangeNotifierProvider<HimaSuggestController>.value(
          value: HimaSuggestController(suggestBridge),
        ),
      ],
      child: HimaApp(config: config),
    ),
  );
}
