import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/destinations/data/oauth/pkce.dart';

void main() {
  test('generate() produces a URL-safe verifier and matching S256 challenge', () {
    final pair = PkcePair.generate();

    final urlSafe = RegExp(r'^[A-Za-z0-9_-]+$');
    expect(urlSafe.hasMatch(pair.verifier), isTrue);
    expect(urlSafe.hasMatch(pair.challenge), isTrue);
    expect(pair.verifier, isNot(equals(pair.challenge)));
  });

  test('generate() produces a fresh pair every call', () {
    final a = PkcePair.generate();
    final b = PkcePair.generate();
    expect(a.verifier, isNot(equals(b.verifier)));
  });
}
