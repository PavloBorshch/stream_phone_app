import 'dart:convert';
import 'dart:math';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

/// Twitch account link result: enough to build a [StreamDestination]
/// (rtmp://live.twitch.tv/app + this stream key).
class TwitchLinkResult {
  const TwitchLinkResult({required this.loginName, required this.streamKey});

  final String loginName;
  final String streamKey;
}

/// Links a Twitch account and fetches its RTMP stream key, entirely
/// client-side.
///
/// Twitch has no PKCE support for the authorization-code grant (verified
/// against Twitch's own docs, 2026-08-18) — public clients without a
/// backend are explicitly directed to the **implicit grant** flow instead
/// (`response_type=token`), which returns the access token straight in the
/// redirect URL's fragment, no token-exchange call needed. That's what this
/// client uses.
///
/// Requires a real Twitch app registered at https://dev.twitch.tv/console/apps
/// with an OAuth Redirect URL of `https://$_httpsHost$_httpsPath` —
/// [clientId] below is that app's real client id. Twitch (like most
/// OAuth providers now) rejects non-HTTPS redirect URIs outright — a custom
/// URL scheme (`streamphonecam://...`) doesn't pass their app-registration
/// validation, confirmed by a real "Redirect URIs must use the HTTPS
/// protocol" error. `flutter_web_auth_2` supports this via
/// `callbackUrlScheme: 'https'` + `httpsHost`/`httpsPath`, which routes the
/// callback through Android App Links / iOS Universal Links instead of a
/// custom scheme. This reuses the same `stream-phone-cam.firebaseapp.com`
/// domain + SHA-256 fingerprint verification already needed for the email
/// sign-in link (`AuthRepository`'s doc comment) rather than standing up
/// anything new — see the `<data android:path="/oauth-callback/...">`
/// entries on `CallbackActivity` in AndroidManifest.xml.
class TwitchOAuthClient {
  TwitchOAuthClient({this.clientId = '3lf8b3o5oriv4ygt6phm48xdg5fga3'});

  final String clientId;

  static const _httpsHost = 'stream-phone-cam.firebaseapp.com';
  static const _httpsPath = '/oauth-callback/twitch';

  static const _scopes = ['channel:read:stream_key'];

  Future<TwitchLinkResult> link() async {
    final state = _randomState();
    final authorizeUrl = Uri.https('id.twitch.tv', '/oauth2/authorize', {
      'client_id': clientId,
      'redirect_uri': 'https://$_httpsHost$_httpsPath',
      'response_type': 'token',
      'scope': _scopes.join(' '),
      'state': state,
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authorizeUrl.toString(),
      callbackUrlScheme: 'https',
      options: const FlutterWebAuth2Options(httpsHost: _httpsHost, httpsPath: _httpsPath),
    );

    final fragment = Uri.parse(result).fragment;
    final params = Uri.splitQueryString(fragment);
    if (params['state'] != state) {
      throw StateError('Twitch OAuth state mismatch — possible CSRF, aborting.');
    }
    final accessToken = params['access_token'];
    if (accessToken == null) {
      throw StateError('Twitch did not return an access token: $params');
    }

    final userId = await _fetchUserId(accessToken);
    final streamKey = await _fetchStreamKey(accessToken, userId);
    return TwitchLinkResult(loginName: userId, streamKey: streamKey);
  }

  Future<String> _fetchUserId(String accessToken) async {
    final response = await http.get(
      Uri.https('api.twitch.tv', '/helix/users'),
      headers: {'Authorization': 'Bearer $accessToken', 'Client-Id': clientId},
    );
    if (response.statusCode != 200) {
      throw StateError('Twitch /helix/users failed: ${response.statusCode} ${response.body}');
    }
    final data = jsonDecode(response.body)['data'] as List<dynamic>;
    return data.first['id'] as String;
  }

  Future<String> _fetchStreamKey(String accessToken, String broadcasterId) async {
    final response = await http.get(
      Uri.https('api.twitch.tv', '/helix/streams/key', {'broadcaster_id': broadcasterId}),
      headers: {'Authorization': 'Bearer $accessToken', 'Client-Id': clientId},
    );
    if (response.statusCode != 200) {
      throw StateError('Twitch /helix/streams/key failed: ${response.statusCode} ${response.body}');
    }
    final data = jsonDecode(response.body)['data'] as List<dynamic>;
    return data.first['stream_key'] as String;
  }

  String _randomState() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
  }
}
