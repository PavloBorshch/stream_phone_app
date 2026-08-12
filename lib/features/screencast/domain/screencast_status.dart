enum ScreencastStatus { idle, requesting, starting, capturing, paused, stopped, denied, error }

ScreencastStatus _statusFromString(String? value) {
  switch (value) {
    case 'requesting':
      return ScreencastStatus.requesting;
    case 'starting':
      return ScreencastStatus.starting;
    case 'capturing':
      return ScreencastStatus.capturing;
    case 'paused':
      return ScreencastStatus.paused;
    case 'stopped':
      return ScreencastStatus.stopped;
    case 'denied':
      return ScreencastStatus.denied;
    case 'error':
      return ScreencastStatus.error;
    case 'idle':
    default:
      return ScreencastStatus.idle;
  }
}

class ScreencastEvent {
  const ScreencastEvent({
    required this.status,
    this.textureId,
    this.width,
    this.height,
    this.frameCount,
    this.message,
  });

  final ScreencastStatus status;
  final int? textureId;
  final int? width;
  final int? height;
  final int? frameCount;
  final String? message;

  factory ScreencastEvent.fromMap(Map<String, dynamic> map) {
    return ScreencastEvent(
      status: _statusFromString(map['status'] as String?),
      textureId: map['textureId'] as int?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      frameCount: map['frameCount'] as int?,
      message: map['message'] as String?,
    );
  }

  static const idle = ScreencastEvent(status: ScreencastStatus.idle);
}
