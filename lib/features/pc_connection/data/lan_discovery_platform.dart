import 'package:flutter/services.dart';

import '../domain/discovered_pc.dart';

/// Wraps the native LAN-discovery bridge (`_streamphonecam._tcp` mDNS/NSD/
/// Bonjour browse — see HELP.md). Browse-only: this app never advertises
/// itself, only the PC client does.
class LanDiscoveryPlatform {
  static const MethodChannel _methodChannel = MethodChannel('com.streamphonecam/lan_discovery');
  static const EventChannel _eventChannel = EventChannel('com.streamphonecam/lan_discovery_events');

  Future<void> startBrowse() => _methodChannel.invokeMethod('startBrowse');

  Future<void> stopBrowse() => _methodChannel.invokeMethod('stopBrowse');

  /// Emits one event per `found`/`lost` service change — not a snapshot
  /// list. Callers fold this into their own known-services map (see
  /// `LanDiscoveryNotifier`).
  Stream<LanDiscoveryEvent> events() {
    return _eventChannel.receiveBroadcastStream().map(
      (raw) => LanDiscoveryEvent.fromMap(Map<String, dynamic>.from(raw as Map)),
    );
  }
}

enum LanDiscoveryEventType { found, lost, browseError }

LanDiscoveryEventType _typeFromString(String? value) {
  switch (value) {
    case 'lost':
      return LanDiscoveryEventType.lost;
    case 'browseError':
      return LanDiscoveryEventType.browseError;
    case 'found':
    default:
      return LanDiscoveryEventType.found;
  }
}

class LanDiscoveryEvent {
  const LanDiscoveryEvent({required this.type, this.pc, this.message});

  final LanDiscoveryEventType type;

  /// Populated for [LanDiscoveryEventType.found]/[LanDiscoveryEventType.lost].
  final DiscoveredPc? pc;

  /// Populated for [LanDiscoveryEventType.browseError].
  final String? message;

  factory LanDiscoveryEvent.fromMap(Map<String, dynamic> map) {
    final type = _typeFromString(map['type'] as String?);
    return LanDiscoveryEvent(
      type: type,
      pc: type == LanDiscoveryEventType.browseError ? null : DiscoveredPc.fromMap(map),
      message: map['message'] as String?,
    );
  }
}
