import '../../features/capture/domain/capture_mode.dart';
import '../../features/screencast/domain/screencast_status.dart';

/// The cross-cutting session state shared by the capture screen and the
/// settings screen: which capture source is selected and its live status.
class StreamSessionState {
  const StreamSessionState({
    required this.mode,
    required this.screencastEvent,
  });

  final CaptureMode mode;
  final ScreencastEvent screencastEvent;

  static const initial = StreamSessionState(
    mode: CaptureMode.camera,
    screencastEvent: ScreencastEvent.idle,
  );

  StreamSessionState copyWith({
    CaptureMode? mode,
    ScreencastEvent? screencastEvent,
  }) {
    return StreamSessionState(
      mode: mode ?? this.mode,
      screencastEvent: screencastEvent ?? this.screencastEvent,
    );
  }
}
