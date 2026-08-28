import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lan_discovery_platform.dart';
import '../domain/discovered_pc.dart';

final lanDiscoveryPlatformProvider = Provider<LanDiscoveryPlatform>((ref) => LanDiscoveryPlatform());

/// Folds the platform's found/lost event stream into a live list of
/// currently-reachable PCs. `autoDispose` because the discovery radio should
/// only run while a pairing screen that needs it is on screen — unlike
/// `streamSessionProvider`, which is app-lifetime.
class LanDiscoveryNotifier extends AutoDisposeNotifier<List<DiscoveredPc>> {
  final Map<String, DiscoveredPc> _byId = {};

  @override
  List<DiscoveredPc> build() {
    final platform = ref.watch(lanDiscoveryPlatformProvider);

    final subscription = platform.events().listen((event) {
      switch (event.type) {
        case LanDiscoveryEventType.found:
          if (event.pc != null) _byId[event.pc!.pcId] = event.pc!;
        case LanDiscoveryEventType.lost:
          if (event.pc != null) _byId.remove(event.pc!.pcId);
        case LanDiscoveryEventType.browseError:
          break;
      }
      state = _byId.values.toList();
    });

    platform.startBrowse();

    ref.onDispose(() {
      subscription.cancel();
      platform.stopBrowse();
    });

    return const [];
  }
}

final lanDiscoveryProvider = NotifierProvider.autoDispose<LanDiscoveryNotifier, List<DiscoveredPc>>(
  LanDiscoveryNotifier.new,
);
