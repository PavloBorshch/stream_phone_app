import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../camera/presentation/camera_preview_pane.dart';
import '../../screencast/data/screencast_platform.dart';
import '../../screencast/domain/screencast_status.dart';
import '../../screencast/presentation/screencast_preview_pane.dart';
import '../../screencast/presentation/widgets/broadcast_picker_button.dart';
import '../domain/capture_mode.dart';
import 'widgets/capture_mode_toggle.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  static const double _expansionBarHeight = 48;

  final ScreencastPlatform _screencastPlatform = ScreencastPlatform();
  StreamSubscription<ScreencastEvent>? _screencastSubscription;

  CaptureMode _mode = CaptureMode.camera;
  ScreencastEvent _screencastEvent = ScreencastEvent.idle;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _screencastSubscription = _screencastPlatform.events().listen((event) {
      if (mounted) setState(() => _screencastEvent = event);
    });
    // Picks up a screencast that's still running natively from before this
    // widget existed (e.g. the app was closed and reopened while
    // broadcasting) - the event stream alone would otherwise stay silent
    // until the native side next has something new to report.
    _screencastPlatform.getStatus().then((event) {
      if (mounted) setState(() => _screencastEvent = event);
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _screencastSubscription?.cancel();
    super.dispose();
  }

  void _setMode(CaptureMode mode) {
    if (mode == _mode) return;
    // Deliberately leaves _screencastEvent untouched: an in-progress
    // screencast keeps broadcasting in the background when switching to
    // Camera mode, so its status shouldn't be reset to idle here.
    setState(() => _mode = mode);
  }

  void _onRecordButtonTap() {
    switch (_screencastEvent.status) {
      case ScreencastStatus.capturing:
      case ScreencastStatus.paused:
        _screencastPlatform.stopCapture();
        break;
      case ScreencastStatus.requesting:
      case ScreencastStatus.starting:
        break;
      default:
        _screencastPlatform.requestCapture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          const _ExpansionLimitBar(isTop: true),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_mode == CaptureMode.camera)
                  const CameraPreviewPane()
                else
                  ScreencastPreviewPane(event: _screencastEvent),
                SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 8,
                        left: 16,
                        right: 16,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _statusPillText(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                              onPressed: () {
                                debugPrint('Open settings');
                              },
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CaptureModeToggle(mode: _mode, onChanged: _setMode),
                            const SizedBox(height: 16),
                            Center(child: _buildRecordButton()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _ExpansionLimitBar(isTop: false),
        ],
      ),
    );
  }

  String _statusPillText() {
    if (_mode == CaptureMode.camera) {
      return 'FPS: 60 | 0 kbps';
    }
    switch (_screencastEvent.status) {
      case ScreencastStatus.capturing:
        return 'SCREENCAST | LIVE';
      case ScreencastStatus.paused:
        return 'SCREENCAST | PAUSED';
      case ScreencastStatus.requesting:
      case ScreencastStatus.starting:
        return 'SCREENCAST | STARTING';
      default:
        return 'SCREENCAST | IDLE';
    }
  }

  Widget _buildRecordButton() {
    if (_mode == CaptureMode.screencast && Platform.isIOS) {
      return const BroadcastPickerButton();
    }

    final isCapturing = _screencastEvent.status == ScreencastStatus.capturing ||
        _screencastEvent.status == ScreencastStatus.paused;
    final isBusy = _mode == CaptureMode.screencast &&
        (_screencastEvent.status == ScreencastStatus.requesting ||
            _screencastEvent.status == ScreencastStatus.starting);

    return GestureDetector(
      onTap: _mode == CaptureMode.camera
          ? () => debugPrint('Start stream')
          : (isBusy ? null : _onRecordButtonTap),
      child: Container(
        height: 70,
        width: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          color: isBusy ? Colors.grey : Colors.redAccent,
        ),
        child: isBusy
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Icon(
                _mode == CaptureMode.screencast && isCapturing ? Icons.stop : Icons.videocam,
                color: Colors.white,
                size: 32,
              ),
      ),
    );
  }
}

class _ExpansionLimitBar extends StatelessWidget {
  const _ExpansionLimitBar({required this.isTop});

  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _CaptureScreenState._expansionBarHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: isTop ? const BorderSide(color: Colors.white24) : BorderSide.none,
          top: isTop ? BorderSide.none : const BorderSide(color: Colors.white24),
        ),
      ),
    );
  }
}
