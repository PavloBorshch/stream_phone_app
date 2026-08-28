import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/pc_connection/domain/pairing_session.dart';

void main() {
  group('QrPairingPayload', () {
    Map<String, dynamic> validJson({int? exp}) => {
      'v': 1,
      'pcId': 'pc-1',
      'pcName': "Alex's PC",
      'host': '192.168.1.42',
      'port': 58712,
      'wsPath': '/pair',
      'token': 'tok',
      'exp': exp ?? (DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000),
    };

    test('round-trips a well-formed payload', () {
      final payload = QrPairingPayload.fromJsonString(jsonEncode(validJson()));
      expect(payload.pcId, 'pc-1');
      expect(payload.host, '192.168.1.42');
      expect(payload.port, 58712);
      expect(payload.isExpired, isFalse);
    });

    test('marks a payload with a past exp as expired', () {
      final past = DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;
      final payload = QrPairingPayload.fromJsonString(jsonEncode(validJson(exp: past)));
      expect(payload.isExpired, isTrue);
    });

    test('throws FormatException on invalid JSON', () {
      expect(() => QrPairingPayload.fromJsonString('not json'), throwsFormatException);
    });

    test('throws FormatException on unsupported version', () {
      final json = validJson()..['v'] = 2;
      expect(() => QrPairingPayload.fromJsonString(jsonEncode(json)), throwsFormatException);
    });

    test('throws FormatException on missing field', () {
      final json = validJson()..remove('token');
      expect(() => QrPairingPayload.fromJsonString(jsonEncode(json)), throwsFormatException);
    });

    test('falls back to [host] when the PC sent no hosts array', () {
      final payload = QrPairingPayload.fromJsonString(jsonEncode(validJson()));
      expect(payload.hosts, ['192.168.1.42']);
    });

    test('keeps host first and appends the rest of the hosts array', () {
      final json = validJson()..['hosts'] = ['192.168.1.42', '10.0.0.5', '192.168.0.101'];
      final payload = QrPairingPayload.fromJsonString(jsonEncode(json));
      expect(payload.host, '192.168.1.42');
      expect(payload.hosts, ['192.168.1.42', '10.0.0.5', '192.168.0.101']);
    });

    test('de-duplicates host appearing again inside hosts', () {
      final json = validJson()..['hosts'] = ['10.0.0.5', '192.168.1.42'];
      final payload = QrPairingPayload.fromJsonString(jsonEncode(json));
      expect(payload.hosts, ['192.168.1.42', '10.0.0.5']);
    });

    test('drops malformed hosts entries instead of rejecting the payload', () {
      final json = validJson()..['hosts'] = ['10.0.0.5', '', 42, null];
      final payload = QrPairingPayload.fromJsonString(jsonEncode(json));
      expect(payload.hosts, ['192.168.1.42', '10.0.0.5']);
    });
  });

  group('PairingCandidate', () {
    test('fromQr uses token auth', () {
      final payload = QrPairingPayload.fromJson({
        'v': 1,
        'pcId': 'pc-1',
        'pcName': 'PC',
        'host': 'h',
        'port': 1,
        'wsPath': '/pair',
        'token': 'tok',
        'exp': DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
      });
      final candidate = PairingCandidate.fromQr(payload);
      expect(candidate.authMethod, PairingAuthMethod.token);
      expect(candidate.token, 'tok');
      expect(candidate.pin, isNull);
    });

    test('fromQr carries every advertised host through to the dial list', () {
      final payload = QrPairingPayload.fromJson({
        'v': 1,
        'pcId': 'pc-1',
        'pcName': 'PC',
        'host': '192.168.0.101',
        'hosts': ['192.168.0.101', '192.168.1.50'],
        'port': 58712,
        'wsPath': '/pair',
        'token': 'tok',
        'exp': DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
      });
      final candidate = PairingCandidate.fromQr(payload);
      expect(candidate.hosts, ['192.168.0.101', '192.168.1.50']);
      expect(candidate.host, '192.168.0.101');
    });

    test('fromManualEntry uses pin auth', () {
      final candidate = PairingCandidate.fromManualEntry(host: '10.0.0.1', port: 58712, pin: '123456');
      expect(candidate.authMethod, PairingAuthMethod.pin);
      expect(candidate.pin, '123456');
      expect(candidate.token, isNull);
    });
  });
}
