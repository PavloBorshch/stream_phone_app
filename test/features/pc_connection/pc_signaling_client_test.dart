import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/pc_connection/data/pc_signaling_client.dart';
import 'package:stream_phone_cam/features/pc_connection/domain/pairing_session.dart';

/// `192.0.2.0/24` is TEST-NET-1 (RFC 5737) — reserved for documentation and
/// guaranteed never to be routable, so dialling it reproduces exactly the
/// failure mode this feature exists for: a host the phone has no route to,
/// which times out silently rather than refusing fast.
const _unreachableHost = '192.0.2.1';
const _otherUnreachableHost = '192.0.2.2';

/// A minimal stand-in for the PC's `/pair` server (HELP.md §4): accepts the
/// WebSocket upgrade and answers `hello` with a successful `hello_ack`.
Future<HttpServer> _startFakePairingServer({String pcId = 'pc-1', String pcName = 'Fake PC'}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      if (message['type'] != 'hello') return;
      socket.add(
        jsonEncode({
          'type': 'hello_ack',
          'ok': true,
          'pcId': pcId,
          'pcName': pcName,
          'token': 'issued-token',
          'protocolVersion': 1,
        }),
      );
    });
  });
  return server;
}

void main() {
  group('PcSignalingClient.connect address racing', () {
    late HttpServer server;

    setUp(() async {
      server = await _startFakePairingServer();
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('reaches the PC even when an unreachable address is listed first', () async {
      // The regression this guards: with serial dialling, the dead address
      // would burn the whole connect timeout before 127.0.0.1 was ever
      // tried, and pairing would fail on a network where the PC *is*
      // reachable — the multi-router case.
      final client = PcSignalingClient(
        PairingCandidate(
          hosts: [_unreachableHost, '127.0.0.1'],
          port: server.port,
          wsPath: '/pair',
          authMethod: PairingAuthMethod.pin,
          pin: '123456',
        ),
      );
      addTearDown(client.close);

      await client.connect(connectTimeout: const Duration(seconds: 5));

      expect(client.connectedHost, '127.0.0.1');
    });

    test('pairOnce reports the address that actually answered', () async {
      final result = await PcSignalingClient.pairOnce(
        PairingCandidate(
          hosts: [_unreachableHost, '127.0.0.1'],
          port: server.port,
          wsPath: '/pair',
          authMethod: PairingAuthMethod.pin,
          pin: '123456',
        ),
      );

      expect(result.host, '127.0.0.1');
      expect(result.pcId, 'pc-1');
      expect(result.token, 'issued-token');
    });

    test('throws PcUnreachableException listing every address when all fail', () async {
      final client = PcSignalingClient(
        PairingCandidate(
          hosts: [_unreachableHost, _otherUnreachableHost],
          port: 58712,
          wsPath: '/pair',
          authMethod: PairingAuthMethod.pin,
          pin: '123456',
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.connect(connectTimeout: const Duration(milliseconds: 400)),
        throwsA(
          isA<PcUnreachableException>().having(
            (e) => e.failures.keys,
            'failures',
            containsAll([_unreachableHost, _otherUnreachableHost]),
          ),
        ),
      );
    });

    test('a single reachable address still works (no regression)', () async {
      final client = PcSignalingClient(
        PairingCandidate(
          hosts: const ['127.0.0.1'],
          port: server.port,
          wsPath: '/pair',
          authMethod: PairingAuthMethod.pin,
          pin: '123456',
        ),
      );
      addTearDown(client.close);

      await client.connect();

      expect(client.connectedHost, '127.0.0.1');
    });
  });
}
