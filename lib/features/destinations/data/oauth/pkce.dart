import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// RFC 7636 PKCE code_verifier/code_challenge pair, used by [KickOAuthClient]
/// (Kick's authorize step requires it) — Twitch's implicit-grant flow
/// (`TwitchOAuthClient`) doesn't use PKCE at all, see its doc comment.
class PkcePair {
  const PkcePair({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;

  factory PkcePair.generate() {
    final random = Random.secure();
    final verifierBytes = List<int>.generate(64, (_) => random.nextInt(256));
    final verifier = base64UrlEncode(verifierBytes).replaceAll('=', '');
    final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    return PkcePair(verifier: verifier, challenge: challenge);
  }
}
