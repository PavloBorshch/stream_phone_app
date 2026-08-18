import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/stream_session_provider.dart';
import '../../camera/presentation/camera_preview_pane.dart';
import '../../screencast/domain/screencast_status.dart';
import '../../screencast/presentation/screencast_preview_pane.dart';
import '../../screencast/presentation/widgets/broadcast_picker_button.dart';
import '../domain/capture_mode.dart';
import 'widgets/capture_mode_toggle.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  static const double _expansionBarHeight = 48;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onRecordButtonTap(ScreencastEvent screencastEvent) {
    final platform = ref.read(screencastPlatformProvider);
    switch (screencastEvent.status) {
      case ScreencastStatus.capturing:
      case ScreencastStatus.paused:
        platform.stopCapture();
        break;
      case ScreencastStatus.requesting:
      case ScreencastStatus.starting:
        break;
      default:
        platform.requestCapture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(streamSessionProvider);
    final mode = session.mode;
    final screencastEvent = session.screencastEvent;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          const _ExpansionLimitBar(isTop: true),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (mode == CaptureMode.camera)
                  const CameraPreviewPane()
                else
                  ScreencastPreviewPane(event: screencastEvent),
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
                                _statusPillText(mode, screencastEvent),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                              onPressed: () => context.push('/settings'),
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
                            CaptureModeToggle(
                              mode: mode,
                              onChanged: (newMode) =>
                                  ref.read(streamSessionProvider.notifier).setMode(newMode),
                            ),
                            const SizedBox(height: 16),
                            Center(child: _buildRecordButton(mode, screencastEvent)),
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

  String _statusPillText(CaptureMode mode, ScreencastEvent screencastEvent) {
    if (mode == CaptureMode.camera) {
      return 'FPS: 60 | 0 kbps';
    }
    switch (screencastEvent.status) {
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

  Widget _buildRecordButton(CaptureMode mode, ScreencastEvent screencastEvent) {
    if (mode == CaptureMode.screencast && Platform.isIOS) {
      return const BroadcastPickerButton();
    }

    final isCapturing = screencastEvent.status == ScreencastStatus.capturing ||
        screencastEvent.status == ScreencastStatus.paused;
    final isBusy = mode == CaptureMode.screencast &&
        (screencastEvent.status == ScreencastStatus.requesting ||
            screencastEvent.status == ScreencastStatus.starting);

    return GestureDetector(
      onTap: mode == CaptureMode.camera
          ? () => debugPrint('Start stream')
          : (isBusy ? null : () => _onRecordButtonTap(screencastEvent)),
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
                mode == CaptureMode.screencast && isCapturing ? Icons.stop : Icons.videocam,
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
