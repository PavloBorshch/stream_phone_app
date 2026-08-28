import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/secure_token_store_provider.dart';
import '../../../core/persistence/settings_repository_provider.dart';
import '../data/paired_pc_repository.dart';
import '../domain/paired_pc.dart';

final pairedPcRepositoryProvider = Provider<PairedPcRepository>((ref) {
  return PairedPcRepository(ref.watch(settingsRepositoryProvider), ref.watch(secureTokenStoreProvider));
});

class PairedPcsNotifier extends Notifier<AsyncValue<List<PairedPc>>> {
  @override
  AsyncValue<List<PairedPc>> build() {
    return AsyncValue.data(ref.watch(pairedPcRepositoryProvider).read());
  }

  Future<void> _reload() async {
    state = AsyncValue.data(ref.read(pairedPcRepositoryProvider).read());
  }

  Future<PairedPc> addFromPairing({
    required String pcId,
    required String displayName,
    required String host,
    List<String> allHosts = const [],
    required int port,
    required String wsPath,
    required String token,
  }) async {
    final pc = await ref
        .read(pairedPcRepositoryProvider)
        .addFromPairing(
          pcId: pcId,
          displayName: displayName,
          host: host,
          allHosts: allHosts,
          port: port,
          wsPath: wsPath,
          token: token,
        );
    await _reload();
    return pc;
  }

  Future<void> remove(String pcId) async {
    await ref.read(pairedPcRepositoryProvider).remove(pcId);
    await _reload();
  }

  Future<void> updateLastKnownAddress(String pcId, {required String host, required int port}) async {
    await ref.read(pairedPcRepositoryProvider).updateLastKnownAddress(pcId, host: host, port: port);
    await _reload();
  }
}

final pairedPcsProvider = NotifierProvider<PairedPcsNotifier, AsyncValue<List<PairedPc>>>(PairedPcsNotifier.new);
