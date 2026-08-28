import 'package:connectivity_plus/connectivity_plus.dart';

import '../domain/active_network.dart';

/// Thin wrapper over `connectivity_plus`, so the policy code depends on
/// [ActiveNetwork] rather than on the plugin's multi-transport list — and so
/// it can be faked in tests without a platform channel.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<ActiveNetwork> current() async {
    return ActiveNetwork.fromConnectivity(await _connectivity.checkConnectivity());
  }

  Stream<ActiveNetwork> changes() {
    return _connectivity.onConnectivityChanged.map(ActiveNetwork.fromConnectivity);
  }
}
