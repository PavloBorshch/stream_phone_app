/// A PC this app has completed at least one successful pairing handshake
/// with. The actual bearer token lives in [SecureTokenStore] under
/// [secureTokenId], never here — this model only carries the reference, same
/// pattern as `StreamDestination.secureKeyId`.
class PairedPc {
  const PairedPc({
    required this.pcId,
    required this.displayName,
    required this.lastKnownHost,
    required this.otherKnownHosts,
    required this.lastKnownPort,
    required this.wsPath,
    required this.secureTokenId,
    required this.pairedAt,
  });

  final String pcId;
  final String displayName;

  /// The address that answered on the most recent successful pairing — the
  /// first one tried on reconnect.
  final String lastKnownHost;

  /// The PC's *other* advertised addresses, excluding [lastKnownHost].
  ///
  /// Kept so a reconnect can race every interface the PC offered (see
  /// [knownHosts]): a PC on both Ethernet and Wi-Fi may only be reachable
  /// on one of them depending on which router the phone is currently
  /// joined to, and that can differ from the network pairing happened on.
  final List<String> otherKnownHosts;

  final int lastKnownPort;
  final String wsPath;
  final String secureTokenId;
  final DateTime pairedAt;

  /// Every address to dial on reconnect, most-recently-working first.
  List<String> get knownHosts => [lastKnownHost, ...otherKnownHosts];

  factory PairedPc.fromJson(Map<String, dynamic> json) {
    final lastKnownHost = json['lastKnownHost'] as String;
    // `otherKnownHosts` is absent in records written before multi-address
    // support; such a PC simply has the single address it paired on.
    final others = json['otherKnownHosts'];
    return PairedPc(
      pcId: json['pcId'] as String,
      displayName: json['displayName'] as String,
      lastKnownHost: lastKnownHost,
      otherKnownHosts: [
        if (others is List)
          for (final h in others)
            if (h is String && h.isNotEmpty && h != lastKnownHost) h,
      ],
      lastKnownPort: json['lastKnownPort'] as int,
      wsPath: json['wsPath'] as String,
      secureTokenId: json['secureTokenId'] as String,
      pairedAt: DateTime.parse(json['pairedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'pcId': pcId,
    'displayName': displayName,
    'lastKnownHost': lastKnownHost,
    'otherKnownHosts': otherKnownHosts,
    'lastKnownPort': lastKnownPort,
    'wsPath': wsPath,
    'secureTokenId': secureTokenId,
    'pairedAt': pairedAt.toIso8601String(),
  };

  PairedPc copyWith({String? lastKnownHost, List<String>? otherKnownHosts, int? lastKnownPort}) {
    return PairedPc(
      pcId: pcId,
      displayName: displayName,
      lastKnownHost: lastKnownHost ?? this.lastKnownHost,
      otherKnownHosts: otherKnownHosts ?? this.otherKnownHosts,
      lastKnownPort: lastKnownPort ?? this.lastKnownPort,
      wsPath: wsPath,
      secureTokenId: secureTokenId,
      pairedAt: pairedAt,
    );
  }
}
