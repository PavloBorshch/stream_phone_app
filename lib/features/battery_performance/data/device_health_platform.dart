import 'package:flutter/services.dart';

import '../domain/device_health.dart';

/// Dart side of `DeviceHealthPlugin.kt` / `DeviceHealthChannel.swift`,
/// following `ScreencastPlatform`'s method-plus-event-channel shape.
///
/// Only thermal state comes over this channel; battery level is
/// `battery_plus`'s job (PLAN.md Phase 7), so there is exactly one source of
/// truth for each.
class DeviceHealthPlatform {
  static const MethodChannel _methodChannel = MethodChannel('com.streamphonecam/device_health');
  static const EventChannel _eventChannel =
      EventChannel('com.streamphonecam/device_health_events');

  Future<ThermalStatus> getStatus() async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>('getStatus');
    if (raw == null) return ThermalStatus.unknown;
    return ThermalStatus.fromCode(raw['thermalStatus'] as int?);
  }

  Stream<ThermalStatus> events() {
    return _eventChannel.receiveBroadcastStream().map(
      (raw) => ThermalStatus.fromCode(
        Map<String, dynamic>.from(raw as Map)['thermalStatus'] as int?,
      ),
    );
  }
}
