import 'package:flutter/services.dart';
import '../domain/screencast_status.dart';

class ScreencastPlatform {
  static const MethodChannel _methodChannel = MethodChannel('com.streamphonecam/screencast');
  static const EventChannel _eventChannel = EventChannel('com.streamphonecam/screencast_events');

  Future<void> requestCapture() => _methodChannel.invokeMethod('requestCapture');

  Future<void> stopCapture() => _methodChannel.invokeMethod('stopCapture');

  Future<ScreencastEvent> getStatus() async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>('getStatus');
    if (raw == null) return ScreencastEvent.idle;
    return ScreencastEvent.fromMap(raw);
  }

  Stream<ScreencastEvent> events() {
    return _eventChannel.receiveBroadcastStream().map(
      (raw) => ScreencastEvent.fromMap(Map<String, dynamic>.from(raw as Map)),
    );
  }
}
