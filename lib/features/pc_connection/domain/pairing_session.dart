import 'dart:convert';

/// The QR code shown by the PC client (see HELP.md's "QR payload" section
/// for the authoritative schema). This app only ever *scans* — it never
/// generates or displays one, per the pairing-direction decision in
/// PLAN.md's Phase 4 entry.
class QrPairingPayload {
  const QrPairingPayload({
    required this.pcId,
    required this.pcName,
    required this.host,
    required this.hosts,
    required this.port,
    required this.wsPath,
    required this.token,
    required this.expiresAt,
  });

  static const supportedVersion = 1;

  final String pcId;
  final String pcName;

  /// The PC's primary LAN IP — `hosts.first`, kept as its own field because
  /// the wire format's `host` is still required (see [hosts]).
  final String host;

  /// Every LAN address the PC believes it is reachable at, primary first.
  ///
  /// A PC with more than one active interface (e.g. Ethernet to one router
  /// and Wi-Fi to another) has no way to know which of its addresses the
  /// phone can actually route to, so it advertises all of them and the
  /// phone races them ([PcSignalingClient.connect]). Falls back to
  /// `[host]` for PC clients that predate the `hosts` field.
  final List<String> hosts;

  final int port;
  final String wsPath;
  final String token;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Throws [FormatException] if [raw] isn't valid JSON, is missing a
  /// required field, or declares an unsupported schema version — the QR
  /// scanner surfaces that as "Invalid QR code" rather than crashing.
  factory QrPairingPayload.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('QR payload is not a JSON object');
    }
    return QrPairingPayload.fromJson(decoded);
  }

  factory QrPairingPayload.fromJson(Map<String, dynamic> json) {
    final version = json['v'] as int?;
    if (version != supportedVersion) {
      throw FormatException('Unsupported QR payload version: $version');
    }
    try {
      final host = json['host'] as String;
      return QrPairingPayload(
        pcId: json['pcId'] as String,
        pcName: json['pcName'] as String,
        host: host,
        hosts: _parseHosts(json, primary: host),
        port: json['port'] as int,
        wsPath: json['wsPath'] as String,
        token: json['token'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch((json['exp'] as int) * 1000, isUtc: true),
      );
    } on TypeError catch (e) {
      throw FormatException('QR payload missing/malformed field: $e');
    }
  }

  /// Builds the ordered, de-duplicated address list from the optional
  /// `hosts` array, always keeping [primary] first. Non-string or empty
  /// entries are dropped rather than throwing — a PC advertising one junk
  /// address shouldn't make an otherwise-valid QR unscannable.
  static List<String> _parseHosts(Map<String, dynamic> json, {required String primary}) {
    final hosts = <String>[primary];
    final raw = json['hosts'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is String && entry.isNotEmpty && !hosts.contains(entry)) {
          hosts.add(entry);
        }
      }
    }
    return List.unmodifiable(hosts);
  }
}

/// How a hello proves it may connect.
///
/// [usb] carries no secret at all: the connection reached the PC through
/// its own `adb reverse` tunnel, which only exists because this phone's
/// owner approved that PC's key in Android's "Allow USB debugging?"
/// prompt. The PC accepts it *only* from a loopback peer, so it can never
/// be used over a network.
enum PairingAuthMethod { token, pin, usb }

/// What's needed to attempt a pairing handshake, regardless of whether it
/// came from a scanned QR or manual host/PIN entry.
class PairingCandidate {
  const PairingCandidate({
    required this.hosts,
    required this.port,
    required this.wsPath,
    required this.authMethod,
    this.pcId,
    this.token,
    this.pin,
  }) : assert(hosts.length > 0, 'a candidate needs at least one host to dial');

  factory PairingCandidate.fromQr(QrPairingPayload payload) {
    return PairingCandidate(
      hosts: payload.hosts,
      port: payload.port,
      wsPath: payload.wsPath,
      authMethod: PairingAuthMethod.token,
      pcId: payload.pcId,
      token: payload.token,
    );
  }

  factory PairingCandidate.fromManualEntry({required String host, required int port, required String pin}) {
    return PairingCandidate(hosts: [host], port: port, wsPath: '/pair', authMethod: PairingAuthMethod.pin, pin: pin);
  }

  /// Connects to a PC found on the USB tunnel with no pairing step at all.
  ///
  /// Always loopback, because that is what the tunnel is -- and what the PC
  /// requires before it will accept [PairingAuthMethod.usb].
  factory PairingCandidate.overUsb({
    required String pcId,
    required int port,
    required String wsPath,
  }) {
    return PairingCandidate(
      hosts: const ['127.0.0.1'],
      port: port,
      wsPath: wsPath,
      authMethod: PairingAuthMethod.usb,
      pcId: pcId,
    );
  }

  /// Every address to try, in preference order. More than one when the PC
  /// advertised several interfaces (see [QrPairingPayload.hosts]) or when
  /// reconnecting to a `PairedPc` with several remembered addresses;
  /// [PcSignalingClient.connect] dials them concurrently and keeps the
  /// first that answers.
  final List<String> hosts;

  final int port;
  final String wsPath;
  final PairingAuthMethod authMethod;
  final String? pcId;
  final String? token;
  final String? pin;

  /// The preferred address — what UI shows before a connection has picked
  /// a winner.
  String get host => hosts.first;
}
