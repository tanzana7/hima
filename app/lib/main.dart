import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'data/api_client.dart';
import 'data/app_config.dart';
import 'data/http_api_client.dart';
import 'data/mock_api_client.dart';
import 'state/app_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig.fromEnvironment;
  // No API_BASE_URL means the offline demo: the mock answers every call, which
  // is how the app runs without a server.
  final ApiClient api = config.useMockApi
      ? MockApiClient()
      : HttpApiClient(baseUrl: config.apiBaseUrl);
  final viewModel = AppViewModel(api);
  // A token saved by a previous launch is restored in the background; the login
  // screen stays up until /app/me accepts it.
  unawaited(viewModel.restoreSession());
  runApp(
    ChangeNotifierProvider<AppViewModel>.value(
      value: viewModel,
      child: HimaApp(config: config),
    ),
  );
}
