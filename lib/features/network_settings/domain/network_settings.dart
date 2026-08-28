/// Which networks the app is allowed to publish over.
///
/// This is a *policy*, checked before a stream starts and while one runs — not
/// a description of what the phone is currently connected to (that comes from
/// `connectivityProvider`).
enum PreferredNetwork {
  auto(
    'Auto',
    'Stream over whatever connection is available',
  ),
  wifiOnly(
    'Wi-Fi only',
    'Refuse to start, and stop streaming, on mobile data',
  ),
  cellularAllowed(
    'Allow mobile data',
    'Stream over mobile data, counting it against the cap below',
  );

  const PreferredNetwork(this.displayName, this.description);

  final String displayName;
  final String description;

  static PreferredNetwork fromName(String? name) {
    return PreferredNetwork.values.firstWhere(
      (value) => value.name == name,
      orElse: () => PreferredNetwork.auto,
    );
  }
}

class NetworkSettings {
  const NetworkSettings({
    required this.preferredNetwork,
    required this.cellularDataCapMb,
    required this.warnBeforeCap,
  });

  final PreferredNetwork preferredNetwork;

  /// Monthly-ish mobile-data budget in megabytes. `null` means "don't track a
  /// cap" — deliberately distinct from `0`, which would mean "no data at all"
  /// and would block every cellular stream.
  final int? cellularDataCapMb;

  /// Warn once at [warnThresholdFraction] of the cap, rather than only when it
  /// is already spent. Streaming a few minutes past a cap is expensive, so the
  /// useful warning is the early one.
  final bool warnBeforeCap;

  static const warnThresholdFraction = 0.8;

  static const capOptionsMb = [500, 1000, 2000, 5000, 10000, 20000];

  static const defaults = NetworkSettings(
    // Auto rather than Wi-Fi-only: a phone streaming camera is often
    // deliberately away from Wi-Fi, and a default that refuses to start would
    // read as the app being broken.
    preferredNetwork: PreferredNetwork.auto,
    cellularDataCapMb: null,
    warnBeforeCap: true,
  );

  factory NetworkSettings.fromJson(Map<String, dynamic> json) {
    return NetworkSettings(
      preferredNetwork: PreferredNetwork.fromName(json['preferredNetwork'] as String?),
      cellularDataCapMb: json['cellularDataCapMb'] as int?,
      warnBeforeCap: json['warnBeforeCap'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'preferredNetwork': preferredNetwork.name,
    if (cellularDataCapMb != null) 'cellularDataCapMb': cellularDataCapMb,
    'warnBeforeCap': warnBeforeCap,
  };

  /// [cellularDataCapMb] is cleared by passing [clearCap], since `null` on its
  /// own cannot be told apart from "not supplied" in the usual copyWith idiom.
  NetworkSettings copyWith({
    PreferredNetwork? preferredNetwork,
    int? cellularDataCapMb,
    bool? warnBeforeCap,
    bool clearCap = false,
  }) {
    return NetworkSettings(
      preferredNetwork: preferredNetwork ?? this.preferredNetwork,
      cellularDataCapMb: clearCap ? null : (cellularDataCapMb ?? this.cellularDataCapMb),
      warnBeforeCap: warnBeforeCap ?? this.warnBeforeCap,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NetworkSettings &&
        other.preferredNetwork == preferredNetwork &&
        other.cellularDataCapMb == cellularDataCapMb &&
        other.warnBeforeCap == warnBeforeCap;
  }

  @override
  int get hashCode => Object.hash(preferredNetwork, cellularDataCapMb, warnBeforeCap);
}
