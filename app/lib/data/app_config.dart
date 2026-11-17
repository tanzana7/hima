/// Build-time configuration, supplied with `--dart-define`.
///
/// Nothing here is a secret: the API base URL and the Discord client id are both
/// public values that the server team registers on their side.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.discordClientId});

  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
    discordClientId: String.fromEnvironment('DISCORD_CLIENT_ID'),
  );

  /// Root URL of the API server, e.g. `http://10.0.2.2:8000` for the Android
  /// emulator. Every app endpoint lives under `/app`.
  final String apiBaseUrl;

  final String discordClientId;

  /// With no base URL the app runs on the offline mock, exactly as before.
  bool get useMockApi => apiBaseUrl.isEmpty;

  /// Discord login needs both the server and the client id.
  bool get canLoginWithDiscord => !useMockApi && discordClientId.isNotEmpty;
}
