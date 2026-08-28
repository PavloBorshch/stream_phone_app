import 'package:flutter/services.dart';

import '../domain/camera_capture_status.dart';

/// Dart side of the native camera capture layer (`CameraEncodeSession.kt` /
/// `CameraEncodeSession.swift`), following `ScreencastPlatform`'s
/// method-channel-plus-event-channel shape.
///
/// This replaces the `camera` package: that plugin opens the sensor for
/// preview only and cannot also hand frames to an encoder, whereas the whole
/// point of Phase 5's capture layer is one open camera feeding a preview
/// texture *and* the encoder(s) at once (PLAN.md §1.4).
class CameraCapturePlatform {
  static const MethodChannel _methodChannel = MethodChannel('com.streamphonecam/camera');
  static const EventChannel _eventChannel = EventChannel('com.streamphonecam/camera_events');

  /// Starts (or re-attaches) the preview and returns its texture id.
  Future<int?> startPreview({
    required int width,
    required int height,
    bool? front,
  }) {
    return _methodChannel.invokeMethod<int>('startPreview', {
      'width': width,
      'height': height,
      'front': ?front,
    });
  }

  Future<int?> switchCamera({required int width, required int height}) {
    return _methodChannel.invokeMethod<int>('switchCamera', {
      'width': width,
      'height': height,
    });
  }

  /// Asks the native side to release the camera. It declines while a stream
  /// is live — capture has to outlive the preview widget, which is why the
  /// decision is made natively rather than here.
  Future<void> stopPreview() => _methodChannel.invokeMethod('stopPreview');

  Future<CameraCaptureEvent> getStatus() async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>('getStatus');
    if (raw == null) return CameraCaptureEvent.idle;
    return CameraCaptureEvent.fromMap(raw);
  }

  Stream<CameraCaptureEvent> events() {
    return _eventChannel.receiveBroadcastStream().map(
      (raw) => CameraCaptureEvent.fromMap(Map<String, dynamic>.from(raw as Map)),
    );
  }
}
