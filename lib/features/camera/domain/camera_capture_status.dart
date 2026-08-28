enum CameraCaptureStatus { idle, running, error }

CameraCaptureStatus _statusFromString(String? value) {
  switch (value) {
    case 'running':
      return CameraCaptureStatus.running;
    case 'error':
      return CameraCaptureStatus.error;
    case 'idle':
    default:
      return CameraCaptureStatus.idle;
  }
}

/// State of the native capture session that feeds both the preview texture
/// and the encoder (PLAN.md §1.4) — the replacement for the `camera` plugin's
/// `CameraController.value`, which only ever described a preview.
class CameraCaptureEvent {
  const CameraCaptureEvent({
    required this.status,
    this.textureId,
    this.width,
    this.height,
    this.lensFacingFront = false,
    this.hasMultipleCameras = false,
    this.message,
  });

  final CameraCaptureStatus status;

  /// Flutter texture the mixer's composited output is drawn into. Changes
  /// whenever a new engine attaches, since a texture entry belongs to the
  /// engine that registered it.
  final int? textureId;
  final int? width;
  final int? height;
  final bool lensFacingFront;
  final bool hasMultipleCameras;
  final String? message;

  static const idle = CameraCaptureEvent(status: CameraCaptureStatus.idle);

  bool get isPreviewReady =>
      status == CameraCaptureStatus.running && textureId != null;

  factory CameraCaptureEvent.fromMap(Map<String, dynamic> map) {
    return CameraCaptureEvent(
      status: _statusFromString(map['status'] as String?),
      textureId: map['textureId'] as int?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      lensFacingFront: map['lensFacingFront'] as bool? ?? false,
      hasMultipleCameras: map['hasMultipleCameras'] as bool? ?? false,
      message: map['message'] as String?,
    );
  }
}
