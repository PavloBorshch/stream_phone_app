import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/pc_connection/domain/paired_pc.dart';

void main() {
  group('PairedPc multi-address memory', () {
    Map<String, dynamic> legacyJson() => {
      'pcId': 'pc-1',
      'displayName': 'Desk PC',
      'lastKnownHost': '192.168.0.101',
      'lastKnownPort': 58712,
      'wsPath': '/pair',
      'secureTokenId': 'tok-id',
      'pairedAt': DateTime.utc(2026, 8, 22).toIso8601String(),
    };

    test('reads records written before multi-address support', () {
      // Pairings persisted by an earlier build have no otherKnownHosts key;
      // they must keep working rather than throwing on load.
      final pc = PairedPc.fromJson(legacyJson());
      expect(pc.otherKnownHosts, isEmpty);
      expect(pc.knownHosts, ['192.168.0.101']);
    });

    test('dials the last working address first, then the alternatives', () {
      final pc = PairedPc.fromJson(
        legacyJson()..['otherKnownHosts'] = ['192.168.1.50', '10.0.0.7'],
      );
      expect(pc.knownHosts, ['192.168.0.101', '192.168.1.50', '10.0.0.7']);
    });

    test('never repeats lastKnownHost inside otherKnownHosts', () {
      final pc = PairedPc.fromJson(
        legacyJson()..['otherKnownHosts'] = ['192.168.0.101', '192.168.1.50'],
      );
      expect(pc.otherKnownHosts, ['192.168.1.50']);
      expect(pc.knownHosts, ['192.168.0.101', '192.168.1.50']);
    });

    test('round-trips every address through toJson', () {
      final original = PairedPc.fromJson(
        legacyJson()..['otherKnownHosts'] = ['192.168.1.50'],
      );
      final reloaded = PairedPc.fromJson(original.toJson());
      expect(reloaded.knownHosts, original.knownHosts);
    });
  });
}
