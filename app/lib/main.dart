import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'data/api_client.dart';
import 'data/http_api_client.dart';
import 'data/mock_api_client.dart';
import 'state/app_view_model.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  // Keep the demo usable while the shared API server is being built.
  final ApiClient api = _apiBaseUrl.isEmpty
      ? MockApiClient()
      : HttpApiClient(baseUrl: _apiBaseUrl);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppViewModel(api),
      child: HimaApp(mockMode: _apiBaseUrl.isEmpty),
    ),
  );
}
