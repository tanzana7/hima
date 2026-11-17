import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the app JWT between launches.
///
/// The token is a 30-day JWT with no refresh endpoint, so it is a long-lived
/// credential and belongs in the platform keychain / keystore rather than in
/// plain preferences.
class TokenStore {
  const TokenStore();

  static const _key = 'atsumaro.app_token';
  static const _storage = FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> clear() => _storage.delete(key: _key);
}
