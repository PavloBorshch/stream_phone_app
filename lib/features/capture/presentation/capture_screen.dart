import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/session/stream_session_provider.dart';
import '../../../core/session/stream_session_state.dart';
import '../../camera/presentation/camera_preview_pane.dart';
import '../../screencast/domain/screencast_status.dart';
import '../../screencast/presentation/screencast_preview_pane.dart';
import '../../battery_performance/presentation/battery_performance_provider.dart';
import '../../overlays/presentation/mute_toggle_button.dart';
import '../../overlays/presentation/stream_stats_overlay.dart';
import '../../screencast/presentation/widgets/broadcast_picker_button.dart';
import '../../streaming_engine/domain/publisher_event.dart';
import '../domain/capture_mode.dart';
import 'widgets/broadcast_target_selector.dart';
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
    _applyWakelock(ref.read(batteryPerformanceProvider).keepScreenAwake);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // Released unconditionally: the wakelock belongs to this screen, and
    // leaving it held after leaving the viewfinder would drain the battery
    // for a preview nobody is looking at.
    _applyWakelock(false);
    super.dispose();
  }

  void _applyWakelock(bool enabled) {
    unawaited(
      (enabled ? WakelockPlus.enable() : WakelockPlus.disable()).catchError(
        (Object error) => debugPrint('wakelock failed: $error'),
      ),
    );
  }

  /// Record button. Publishing and screencast capture are separate native
  /// sessions, so the two are sequenced here rather than in the notifier:
  /// stopping a screencast stream stops the projection too, which is what a
  /// user tapping "stop" means, even though the projection would happily
  /// keep running on its own.
  void _onRecordButtonTap(StreamSessionState session) {
    final notifier = ref.read(streamSessionProvider.notifier);

    if (session.isStreaming) {
      notifier.stopStream();
      if (session.mode == CaptureMode.screencast) {
        ref.read(screencastPlatformProvider).stopCapture();
      }
      return;
    }

    notifier.startStream();
  }

  /// Mode toggle. Switching away from a mode with an active screencast
  /// capture (streaming or not) must actually stop it here, for the same
  /// reason [_onRecordButtonTap] sequences the two native calls itself
  /// rather than leaving it to the notifier: HaishinKit's capture session
  /// happily keeps running in the background otherwise — the camera preview
  /// for the *new* mode then opens on top of it, so the phone ends up
  /// running two capture sessions (and, if a stream was live, still
  /// broadcasting a screencast the UI no longer shows) for nothing. This is
  /// deliberately different from navigating to another screen (e.g.
  /// Settings) or the app being backgrounded, both of which must still leave
  /// an active stream running — only the in-app mode toggle stops it.
  void _onModeChanged(StreamSessionState session, CaptureMode newMode) {
    if (session.mode == newMode) return;
    final notifier = ref.read(streamSessionProvider.notifier);

    if (session.isStreaming) {
      notifier.stopStream();
    }
    if (session.mode == CaptureMode.screencast &&
        (session.screencastEvent.status == ScreencastStatus.capturing ||
            session.screencastEvent.status == ScreencastStatus.paused)) {
      ref.read(screencastPlatformProvider).stopCapture();
    }

    notifier.setMode(newMode);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(streamSessionProvider);
    final mode = session.mode;
    final screencastEvent = session.screencastEvent;

    ref.listen<bool>(
      batteryPerformanceProvider.select((settings) => settings.keepScreenAwake),
      (_, next) => _applyWakelock(next),
    );

    // Publishing failures carry a message worth reading in full (a missing
    // stream key, an ingest that refused the connection) — the status pill
    // only has room for the word ERROR.
    ref.listen<StreamSessionState>(streamSessionProvider, (previous, next) {
      final message = next.publisherEvent.message;
      final becameError = next.publisherEvent.status == PublisherStatus.error &&
          previous?.publisherEvent.status != PublisherStatus.error;
      if (becameError && message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }

      // Network warnings (mobile-data cap) are not failures, so they get their
      // own softer presentation and are cleared once shown — the session
      // latches each message so this fires once per distinct warning, not once
      // per stats tick.
      final warning = next.networkWarning;
      if (warning != null && warning != previous?.networkWarning) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warning),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 6),
          ),
        );
        ref.read(streamSessionProvider.notifier).clearNetworkWarning();
      }
    });

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
                                _statusPillText(session),
                                style: TextStyle(
                                  color: session.publisherEvent.status == PublisherStatus.error
                                      ? Colors.redAccent
                                      : Colors.white,
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
                        top: 52,
                        left: 16,
                        child: const StreamStatsOverlay(),
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
                              onChanged: (newMode) => _onModeChanged(session, newMode),
                            ),
                            const SizedBox(height: 8),
                            BroadcastTargetSelector(
                              target: session.broadcastTarget,
                              enabled: !session.isStreaming,
                              onChanged: (target) => ref
                                  .read(streamSessionProvider.notifier)
                                  .setBroadcastTarget(target),
                            ),
                            const SizedBox(height: 16),
                            // A three-slot row rather than a Stack: a Stack
                            // sizes itself to its largest non-positioned
                            // child, so the 70x70 record button made it 70
                            // wide and the side controls landed on top of it.
                            // The Expanded sides keep the record button
                            // exactly centred regardless of what flanks it.
                            SizedBox(
                              height: 70,
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 24),
                                        child: MuteToggleButton(),
                                      ),
                                    ),
                                  ),
                                  _buildRecordButton(session),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 24),
                                        // The record button publishes an
                                        // already-running capture rather than
                                        // tearing it down (restarting it would
                                        // cost another consent dialog), so
                                        // ending a capture that isn't being
                                        // streamed needs its own control.
                                        child: _canStopCaptureOnly(session)
                                            ? IconButton(
                                                tooltip: 'Stop screen capture',
                                                onPressed: () => ref
                                                    .read(screencastPlatformProvider)
                                                    .stopCapture(),
                                                icon: const Icon(
                                                  Icons.stop_screen_share,
                                                  color: Colors.white,
                                                  size: 28,
                                                ),
                                                style: IconButton.styleFrom(
                                                  backgroundColor: Colors.black54,
                                                  padding: const EdgeInsets.all(12),
                                                ),
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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

  /// True when a screencast is running but nothing is being published — the
  /// only state where "stop capture" is a distinct action from "stop
  /// stream". iOS is excluded because a broadcast there is stopped from the
  /// system UI (or the same picker that started it), not by this app.
  bool _canStopCaptureOnly(StreamSessionState session) {
    return session.mode == CaptureMode.screencast &&
        !Platform.isIOS &&
        !session.isStreaming &&
        (session.screencastEvent.status == ScreencastStatus.capturing ||
            session.screencastEvent.status == ScreencastStatus.paused);
  }

  /// Live publishing stats take over the pill whenever a session is running —
  /// they are the same for both capture sources, so the mode-specific text
  /// below only describes the idle/starting states.
  String _statusPillText(StreamSessionState session) {
    final publisher = session.publisherEvent;
    switch (publisher.status) {
      case PublisherStatus.connecting:
        return 'CONNECTING';
      case PublisherStatus.reconnecting:
        return 'RECONNECTING';
      case PublisherStatus.live:
        final parts = <String>[
          'LIVE',
          if (publisher.bitrateKbps != null) '${publisher.bitrateKbps} kbps',
          if (publisher.fps != null) '${publisher.fps} fps',
          if (publisher.droppedFrames != null && publisher.droppedFrames! > 0)
            '${publisher.droppedFrames} dropped',
        ];
        return parts.join(' | ');
      case PublisherStatus.error:
        return 'ERROR';
      case PublisherStatus.idle:
      case PublisherStatus.stopped:
        break;
    }

    if (session.mode == CaptureMode.camera) {
      return 'CAMERA | READY';
    }
    switch (session.screencastEvent.status) {
      case ScreencastStatus.capturing:
        return 'SCREENCAST | CAPTURING';
      case ScreencastStatus.paused:
        return 'SCREENCAST | PAUSED';
      case ScreencastStatus.requesting:
      case ScreencastStatus.starting:
        return 'SCREENCAST | STARTING';
      default:
        return 'SCREENCAST | IDLE';
    }
  }

  Widget _buildRecordButton(StreamSessionState session) {
    final mode = session.mode;
    final screencastEvent = session.screencastEvent;

    // iOS can't start a broadcast programmatically — the system picker is
    // the only legal entry point, so it replaces the record button entirely
    // in screencast mode (publishing then follows the capture, exactly as it
    // does on Android).
    if (mode == CaptureMode.screencast && Platform.isIOS) {
      return const BroadcastPickerButton();
    }

    final isStreaming = session.isStreaming;
    final isBusy = session.publisherEvent.status == PublisherStatus.connecting ||
        (mode == CaptureMode.screencast &&
            (screencastEvent.status == ScreencastStatus.requesting ||
                screencastEvent.status == ScreencastStatus.starting));

    return GestureDetector(
      onTap: isBusy ? null : () => _onRecordButtonTap(session),
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
                isStreaming ? Icons.stop : Icons.videocam,
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
