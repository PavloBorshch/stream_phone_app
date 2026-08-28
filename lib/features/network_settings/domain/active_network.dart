import 'package:connectivity_plus/connectivity_plus.dart';

/// What the phone is actually connected over, reduced to the only distinction
/// this app's policy cares about: is the link metered.
enum ActiveNetwork {
  none('Offline'),
  wifi('Wi-Fi'),
  ethernet('Ethernet'),
  cellular('Mobile data'),
  other('Unknown network');

  const ActiveNetwork(this.displayName);

  final String displayName;

  /// Only mobile data is billed by the byte, so only it is counted against the
  /// cap. [other] is deliberately *not* treated as metered — guessing wrong in
  /// that direction would silently refuse to stream on a Wi-Fi-only setting
  /// over a link that is actually free.
  bool get isMetered => this == ActiveNetwork.cellular;

  /// Maps `connectivity_plus`'s multi-transport answer down to one value.
  ///
  /// The plugin reports every active transport, so `[wifi, mobile]` is normal
  /// while a phone holds both; the OS routes over the unmetered one, so Wi-Fi
  /// and Ethernet win. `satellite` only ever appears alongside `mobile`, and
  /// is even more constrained, so it needs no separate case.
  factory ActiveNetwork.fromConnectivity(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return ActiveNetwork.none;
    }
    if (results.contains(ConnectivityResult.ethernet)) return ActiveNetwork.ethernet;
    if (results.contains(ConnectivityResult.wifi)) return ActiveNetwork.wifi;
    if (results.contains(ConnectivityResult.mobile)) return ActiveNetwork.cellular;
    return ActiveNetwork.other;
  }
}
