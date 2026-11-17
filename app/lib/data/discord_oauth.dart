import 'dart:convert';
import 'dart:math';

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
    final challenge = _base64Url(sha256Bytes(utf8.encode(verifier)));
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

const List<int> _sha256K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

int _rotr(int value, int bits) =>
    ((value >> bits) | (value << (32 - bits))) & 0xffffffff;

/// SHA-256 (FIPS 180-4), used only to derive the PKCE `code_challenge`.
///
/// `package:crypto` would be a third new dependency and this task allows only
/// two, so the digest is implemented here. It is a fixed, fully specified
/// algorithm with no policy decisions of its own.
List<int> sha256Bytes(List<int> message) {
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  final bitLength = message.length * 8;
  final padded = <int>[...message, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    padded.add((bitLength >> shift) & 0xff);
  }

  final w = List<int>.filled(64, 0);
  for (var offset = 0; offset < padded.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final at = offset + i * 4;
      w[i] =
          (padded[at] << 24) |
          (padded[at + 1] << 16) |
          (padded[at + 2] << 8) |
          padded[at + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final temp1 = (h + s1 + ch + _sha256K[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  return [
    for (final word in [h0, h1, h2, h3, h4, h5, h6, h7])
      for (var shift = 24; shift >= 0; shift -= 8) (word >> shift) & 0xff,
  ];
}
