import 'package:uuid/uuid.dart';

import '../../../core/persistence/secure_token_store.dart';
import '../../../core/persistence/settings_repository.dart';
import '../domain/paired_pc.dart';

/// Persists the paired-PC list as one JSON array (via [SettingsRepository])
/// with each PC's bearer token stored separately in [SecureTokenStore],
/// keyed by [PairedPc.secureTokenId]. Mirrors `DestinationsRepository`.
class PairedPcRepository {
  PairedPcRepository(this._settings, this._secureStore);

  static const _key = 'pc_pairings';
  static const _uuid = Uuid();

  final SettingsRepository _settings;
  final SecureTokenStore _secureStore;

  List<PairedPc> read() {
    final json = _settings.readJson(_key);
    if (json == null) return const [];
    final list = json['items'] as List<dynamic>? ?? const [];
    return list.map((e) => PairedPc.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _writeAll(List<PairedPc> pcs) {
    return _settings.writeJson(_key, {'items': pcs.map((p) => p.toJson()).toList()});
  }

  Future<String?> readToken(String secureTokenId) => _secureStore.read(secureTokenId);

  /// Saves a PC that just completed a successful pairing handshake (QR or
  /// PIN). If [pcId] is already paired, its record and token are replaced
  /// rather than duplicated — a rescan/re-pair of the same PC updates it.
  /// [host] is the address that actually answered; [allHosts] is every
  /// address the PC advertised (QR `hosts`), remembered so a later
  /// reconnect from a different network can race the others too.
  Future<PairedPc> addFromPairing({
    required String pcId,
    required String displayName,
    required String host,
    List<String> allHosts = const [],
    required int port,
    required String wsPath,
    required String token,
  }) async {
    final existing = read();
    String? priorTokenId;
    for (final p in existing) {
      if (p.pcId == pcId) priorTokenId = p.secureTokenId;
    }

    final secureTokenId = priorTokenId ?? 'pc_pairing_token_${_uuid.v4()}';
    await _secureStore.write(secureTokenId, token);

    final pc = PairedPc(
      pcId: pcId,
      displayName: displayName,
      lastKnownHost: host,
      otherKnownHosts: [
        for (final h in allHosts)
          if (h != host) h,
      ],
      lastKnownPort: port,
      wsPath: wsPath,
      secureTokenId: secureTokenId,
      pairedAt: DateTime.now(),
    );

    await _writeAll([...existing.where((p) => p.pcId != pcId), pc]);
    return pc;
  }

  Future<void> remove(String pcId) async {
    final pcs = read();
    PairedPc? target;
    for (final p in pcs) {
      if (p.pcId == pcId) target = p;
    }
    if (target == null) return;
    await _secureStore.delete(target.secureTokenId);
    await _writeAll(pcs.where((p) => p.pcId != pcId).toList());
  }

  Future<void> updateLastKnownAddress(String pcId, {required String host, required int port}) async {
    final pcs = read();
    await _writeAll([
      for (final p in pcs)
        if (p.pcId == pcId) p.copyWith(lastKnownHost: host, lastKnownPort: port) else p,
    ]);
  }
}
