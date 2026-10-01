import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/discovered_pc.dart';

/// Finds the PC client over a USB cable, with no network of any kind.
///
/// ## How the cable becomes a connection
///
/// The PC sets up `adb reverse tcp:58712 tcp:58712` for every phone it sees
/// plugged in (see the PC client's `adb_bridge.dart`). That makes port
/// 58712 on *this phone's loopback* come out on the PC's loopback, carried
/// over USB by the adb daemon. So the phone reaches the PC by connecting to
/// `127.0.0.1` — no IP address to discover, no subnet to scan, nothing on
/// the phone to configure, and it works with every radio switched off.
///
/// ## Why "search automatically" is a single probe
///
/// Because the tunnel always lands on the same fixed local port, finding
/// the PC is just asking whether anything is listening there — and the
/// answer arrives in milliseconds. There is nothing to enumerate: a cable
/// either carries a tunnel or it doesn't.
///
/// ## Why the probe is an HTTP GET rather than a bare connect
///
/// A port being open on loopback says nothing about *what* is behind it —
/// on a phone that is plenty of other things. The PC serves an anonymous
/// `GET /info` on the same port returning its `pcId`/`pcName`/`wsPath` (see
/// the PC's `PairingServer.infoPath`), so a match is positive
/// identification rather than a guess. Discovery confers no trust either
/// way: pairing still requires the QR token or PIN.
class UsbBridgeDiscovery {
  const UsbBridgeDiscovery();

  /// Fixed by the PC's `AdbBridge.phoneSignalingPort`. Fixed rather than
  /// negotiated precisely so this end needs no configuration: with several
  /// phones plugged in, each one still uses this same local port, and adb
  /// routes each to its own PC-side port.
  static const int signalingPort = 58712;

  /// Fixed by the PC's `AdbBridge.phoneMediaPort` — where the RTMP leg
  /// publishes. Also per-phone-loopback, also routed per device by adb.
  static const int mediaPort = 58713;

  /// Loopback answers or refuses immediately; there is no network in the
  /// path to be slow. A timeout this short keeps a probe off the critical
  /// path of connecting.
  static const _probeTimeout = Duration(milliseconds: 800);

  /// The RTMP URL the phone publishes its PC leg to when connected by USB.
  static String get mediaPublishUrl => 'rtmp://127.0.0.1:$mediaPort/live/phone';

  /// The PC on the other end of the cable, or null when no tunnel is up.
  ///
  /// Null is the ordinary answer — no cable, USB debugging off, the PC app
  /// not running — so this never throws.
  Future<DiscoveredPc?> find({Duration timeout = _probeTimeout}) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$signalingPort/info'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;

      return DiscoveredPc(
        pcId: json['pcId'] as String,
        pcName: json['pcName'] as String,
        host: '127.0.0.1',
        port: signalingPort,
        wsPath: json['wsPath'] as String? ?? '/pair',
      );
    } catch (e) {
      // Nothing listening, something else listening, a malformed reply --
      // all of them mean "no PC over USB", which is a normal state.
      debugPrint('UsbBridgeDiscovery: no PC on the USB tunnel ($e)');
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
