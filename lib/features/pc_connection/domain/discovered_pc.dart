/// A PC found via LAN discovery (`_streamphonecam._tcp` mDNS/NSD/Bonjour
/// browse — see HELP.md). Being discovered doesn't imply trust: it only
/// tells the app *where* a PC is, not that it's paired — see
/// [PairingCandidate] for the pairing handshake itself.
class DiscoveredPc {
  const DiscoveredPc({required this.pcId, required this.pcName, required this.host, required this.port, required this.wsPath});

  final String pcId;
  final String pcName;
  final String host;
  final int port;
  final String wsPath;

  factory DiscoveredPc.fromMap(Map<String, dynamic> map) {
    return DiscoveredPc(
      pcId: map['pcId'] as String,
      pcName: map['pcName'] as String,
      host: map['host'] as String,
      port: map['port'] as int,
      wsPath: map['wsPath'] as String,
    );
  }
}
