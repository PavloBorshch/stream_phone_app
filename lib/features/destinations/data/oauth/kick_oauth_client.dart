import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'pkce.dart';

/// Thrown by [KickOAuthClient.link] — see its doc comment for why linking
/// isn't actually possible yet.
class KickBackendRequiredException implements Exception {
  const KickBackendRequiredException();

  @override
  String toString() =>
      'Kick account linking needs a backend token-exchange proxy that is not '
      'part of this app yet — use "Custom RTMP" with your Kick stream key '
      '(Creator Dashboard → Settings → Stream) instead.';
}

/// Kick's OAuth (verified against KickEngineering/KickDevDocs, 2026-08-18)
/// is authorization-code + PKCE at https://id.kick.com/oauth/authorize, but
/// its token endpoint (`POST /oauth/token`) still requires `client_secret`
/// alongside `code_verifier` — PKCE alone isn't enough to skip it. A secret
/// can't be embedded in a mobile app without exposing it to anyone who
/// decompiles the APK, so completing this flow needs a small backend that
/// holds the secret and exchanges the code server-side — the same
/// "confidential client" situation PLAN.md §3.1 already flags for Facebook,
/// and new infrastructure outside this repo (like the WAN signaling relay
/// in §3.3).
///
/// [link] performs only the authorize step (real, functional — the browser
/// opens and returns an authorization code) so the client_id/redirect_uri
/// wiring can be verified once a real Kick app is registered, but always
/// throws [KickBackendRequiredException] instead of attempting the token
/// exchange. The custom RTMP form is Kick's working path today.
class KickOAuthClient {
  KickOAuthClient({this.clientId = '01M0BM5F7QFWHECP6XCHWQSSB9'});

  final String clientId;

  // Same HTTPS-redirect requirement and App Link mechanism as
  // TwitchOAuthClient — see its doc comment. Kick's own console requires
  // an HTTPS redirect URI too, not a custom scheme.
  static const _httpsHost = 'stream-phone-cam.firebaseapp.com';
  static const _httpsPath = '/oauth-callback/kick';

  static const _scopes = ['user:read', 'channel:read'];

  Future<Never> link() async {
    final pkce = PkcePair.generate();
    final authorizeUrl = Uri.https('id.kick.com', '/oauth/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': 'https://$_httpsHost$_httpsPath',
      'scope': _scopes.join(' '),
      'state': pkce.verifier.substring(0, 16),
      'code_challenge': pkce.challenge,
      'code_challenge_method': 'S256',
    });

    await FlutterWebAuth2.authenticate(
      url: authorizeUrl.toString(),
      callbackUrlScheme: 'https',
      options: const FlutterWebAuth2Options(httpsHost: _httpsHost, httpsPath: _httpsPath),
    );
    throw const KickBackendRequiredException();
  }
}
