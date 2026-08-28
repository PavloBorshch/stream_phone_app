import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../video_settings/presentation/video_settings_provider.dart';
import '../data/camera_capture_platform.dart';
import '../domain/camera_capture_status.dart';

final cameraCapturePlatformProvider = Provider<CameraCapturePlatform>(
  (ref) => CameraCapturePlatform(),
);

/// Renders the native capture session's preview texture.
///
/// The session itself is owned natively (`PublisherForegroundService`), not by
/// this widget: unmounting the pane — switching to Screencast mode, or the
/// Activity being recreated — must not interrupt a live stream, so this only
/// asks for the camera to stop, and the native side refuses while publishing.
/// That is the same ownership split the screencast pane already relies on.
class CameraPreviewPane extends ConsumerStatefulWidget {
  const CameraPreviewPane({super.key});

  @override
  ConsumerState<CameraPreviewPane> createState() => _CameraPreviewPaneState();
}

class _CameraPreviewPaneState extends ConsumerState<CameraPreviewPane> {
  CameraCaptureEvent _event = CameraCaptureEvent.idle;
  StreamSubscription<CameraCaptureEvent>? _subscription;
  bool _isBusy = true;
  String? _error;

  /// Held rather than re-read on demand because `dispose()` needs it, and
  /// `ref` may not be used once the widget is being torn down.
  late final CameraCapturePlatform _platform = ref.read(cameraCapturePlatformProvider);

  @override
  void initState() {
    super.initState();
    _subscription = _platform.events().listen(
      (event) {
        if (mounted) setState(() => _event = event);
      },
      onError: (Object error) => debugPrint('camera event stream error: $error'),
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    // The preview runs at the configured capture resolution so what the user
    // frames is what the encoder sends — a preview at a different aspect
    // ratio would crop differently from the stream.
    final settings = ref.read(videoSettingsProvider);
    try {
      // Covers the case where capture is already running (a stream in
      // progress from before this pane existed): the native side re-attaches
      // rather than reopening the camera.
      final status = await _platform.getStatus();
      if (mounted) setState(() => _event = status);

      await _platform.startPreview(
        width: settings.resolution.width,
        height: settings.resolution.height,
      );
      if (mounted) setState(() => _isBusy = false);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _error = error.message ?? 'Could not open the camera.';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _error = 'Camera capture is not available on this build yet.';
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_isBusy || !_event.hasMultipleCameras) return;
    setState(() => _isBusy = true);
    final settings = ref.read(videoSettingsProvider);
    try {
      await _platform.switchCamera(
        width: settings.resolution.width,
        height: settings.resolution.height,
      );
    } on PlatformException catch (error) {
      debugPrint('Camera switch error: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // Fire-and-forget: the pane is going away either way, and the native side
    // ignores this while a stream is live.
    unawaited(
      _platform
          .stopPreview()
          .catchError((Object error) => debugPrint('stopPreview failed: $error')),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_event.isPreviewReady) _PreviewTexture(event: _event),
        if (!_event.isPreviewReady)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                    )
                  : const CircularProgressIndicator(color: Colors.redAccent),
            ),
          ),
        SafeArea(
          child: Stack(
            children: [
              Positioned(
                right: 16,
                bottom: 16,
                child: IconButton(
                  onPressed: _event.hasMultipleCameras && !_isBusy ? _switchCamera : null,
                  icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 32),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The raw `Texture` widget has no notion of aspect ratio — laid out
/// directly inside the pane's `Stack(fit: StackFit.expand)`, it stretched
/// non-uniformly to fill the phone's (tall) screen bounds, squeezing a
/// capture buffer at a different aspect ratio (e.g. 16:9) horizontally.
/// Wrapping it in a fixed-size `SizedBox` at the native buffer's own
/// width/height, scaled with `BoxFit.cover` via `FittedBox`, preserves the
/// buffer's real aspect ratio and crops to fill instead of distorting —
/// matching what the record button actually captures.
class _PreviewTexture extends StatelessWidget {
  const _PreviewTexture({required this.event});

  final CameraCaptureEvent event;

  @override
  Widget build(BuildContext context) {
    final width = event.width;
    final height = event.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      // No native size reported (shouldn't happen alongside a textureId,
      // but native contracts change) — fall back to the old stretch-to-fill
      // rather than crashing on a division by zero in FittedBox.
      return Texture(textureId: event.textureId!);
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: Texture(textureId: event.textureId!),
      ),
    );
  }
}
