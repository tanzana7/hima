import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'models/models.dart';

/// Thrown when the user closes the Discord page without finishing.
class DiscordLoginCancelled implements Exception {
  const DiscordLoginCancelled();
}

/// Runs the Discord authorization-code flow with PKCE (S256).
///
/// The redirect URI is `discord-<client id>:/authorize/callback`, Discord's
/// documented mobile format: the scheme itself carries the client id, so the
/// same string has to be registered in the Developer Portal and in the Android
/// manifest (the Gradle build fills the scheme in from the client id).
class DiscordOAuth {
  const DiscordOAuth({required this.clientId});

  final String clientId;

  String get callbackScheme => 'discord-$clientId';

  /// Scheme, one slash, then the path — exactly what the server registers.
  String get redirectUri => '$callbackScheme:/authorize/callback';

  /// Opens the Discord consent page and returns the code exchange request.
  Future<DiscordAuthRequest> authorize() async {
    final verifier = _base64Url(_randomBytes(32));
    final challenge = _base64Url(sha256.convert(utf8.encode(verifier)).bytes);
    final state = _base64Url(_randomBytes(16));
    // Built by hand because `Uri.https` encodes a space in `scope` as `+`, and
    // Discord expects `%20`.
    final query = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'scope': 'identify guilds',
      'redirect_uri': redirectUri,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'consent',
    }.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: 'https://discord.com/oauth2/authorize?$query',
        callbackUrlScheme: callbackScheme,
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') throw const DiscordLoginCancelled();
      rethrow;
    }

    final callback = Uri.parse(result);
    final error = callback.queryParameters['error'];
    if (error != null) {
      if (error == 'access_denied') throw const DiscordLoginCancelled();
      throw PlatformException(
        code: error,
        message: callback.queryParameters['error_description'],
      );
    }
    // The state proves the code belongs to the request this app started.
    if (callback.queryParameters['state'] != state) {
      throw StateError('Discord returned a different state.');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('Discord returned no authorization code.');
    }
    return DiscordAuthRequest(
      code: code,
      codeVerifier: verifier,
      redirectUri: redirectUri,
    );
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return [for (var index = 0; index < length; index++) random.nextInt(256)];
  }

  /// base64url without padding: 32 bytes become the 43 character verifier the
  /// PKCE spec requires.
  static String _base64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
}
