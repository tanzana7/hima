import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/api_client.dart';
import 'data/http_api_client.dart';
import 'data/mock_api_client.dart';
import 'state/app_view_model.dart';
import 'ui/app_root.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  // Keep the demo usable while the shared API server is being built.
  final ApiClient api = _apiBaseUrl.isEmpty
      ? MockApiClient()
      : HttpApiClient(baseUrl: _apiBaseUrl);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppViewModel(api),
      child: AtsumaroApp(mockMode: _apiBaseUrl.isEmpty),
    ),
  );
}

class AtsumaroApp extends StatelessWidget {
  const AtsumaroApp({super.key, required this.mockMode});

  final bool mockMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'あつまろ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF397B6E),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F7F3),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F7F3),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F7F3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: AppRoot(mockMode: mockMode),
  );
}
