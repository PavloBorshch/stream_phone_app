import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../camera/data/camera_capture_platform.dart';
import '../../camera/presentation/camera_preview_pane.dart' show cameraCapturePlatformProvider;
import '../../video_settings/presentation/video_settings_provider.dart';
import '../data/pc_signaling_client.dart';
import '../domain/pairing_session.dart';
import 'paired_pcs_provider.dart';

/// Scans the QR code the PC client displays (see HELP.md's "QR payload"
/// section). This app only ever scans — it never generates/displays a QR
/// itself, per PLAN.md's Phase 4 pairing-direction decision.
///
/// This route is reached via `context.push('/settings/pc-connection/scan')`
/// (see `app_router.dart`) — a `push`, not a `go`/replace — so the whole
/// stack underneath, including `CaptureScreen`'s `CameraPreviewPane`, stays
/// mounted the entire time this page is up; it is only *covered*, never
/// unmounted, so its `dispose()`/`initState()` never run just from this
/// navigation. That matters because `MobileScanner` opens its own,
/// independent camera session (CameraX), and if `CameraPreviewPane`'s own
/// `Camera2Source` is still holding the physical camera at that moment (the
/// common case — nothing about navigating to Settings asks it to let go),
/// the two collide: only one can hold a given camera id open, so
/// `MobileScanner`'s open forcibly disconnects ours instead of us releasing
/// it. The disconnected `Camera2Source` never notifies
/// `CameraEncodeSession` that it died, so `CameraEncodeSession.isRunning`
/// stays (wrongly) true — and since `CameraPreviewPane`'s widget/State is
/// never recreated either (same reason: never unmounted), nothing ever asks
/// to restart it. The result is exactly the reported bug: the phone's own
/// camera preview freezes on its last frame from right around when the QR
/// scan started, and stays frozen indefinitely — until the user taps
/// switch-camera, which (unlike a plain re-attach) always forces a real
/// reopen regardless of that stale state, incidentally curing it. See
/// MISTAKES.md for the full trace.
///
/// The fix applied here has two halves:
/// 1. Release the phone's own camera *before* `MobileScanner` ever mounts
///    (`_releaseCameraForScanning`), so `MobileScanner` opens a camera
///    nothing else is holding instead of stealing it from something that
///    is.
/// 2. Ask the native session to re-attach the preview once this page is
///    done with the camera (`dispose()`). `CameraPreviewPane`'s own
///    `EventChannel` subscription is still alive throughout (its widget was
///    never unmounted), so the fresh texture id this produces flows
///    straight into it and the preview un-freezes — no explicit
///    coordination with `CameraPreviewPane` itself is needed.
class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});

  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage> {
  bool _processing = false;

  /// Null while the phone's own camera release is still in flight — the
  /// scanner must not mount before then (see class doc comment). Once set,
  /// true means the camera came back busy (still live-publishing from the
  /// camera; native declined to release it — see
  /// `PublisherForegroundService.stopCameraPreviewIfIdle`), in which case
  /// scanning would either fail to get the camera or, worse, steal it out
  /// from under an actual live stream, so this page refuses to scan at all
  /// rather than attempting either.
  bool? _cameraBusy;

  /// Held rather than read from `ref` on demand — `dispose()` needs both,
  /// and `ref` is unusable once a `ConsumerState` is being torn down (see
  /// `CameraPreviewPane`'s own doc comment on the same pattern, and
  /// MISTAKES.md's 2026-08-23 entry on the same mistake).
  late final CameraCapturePlatform _cameraPlatform = ref.read(cameraCapturePlatformProvider);
  late final _resolution = ref.read(videoSettingsProvider).resolution;

  @override
  void initState() {
    super.initState();
    unawaited(_releaseCameraForScanning());
  }

  Future<void> _releaseCameraForScanning() async {
    // Mirrors CameraPreviewPane._start()'s catch shape: on a build/device
    // where the camera platform channel isn't there at all
    // (MissingPluginException) or the publisher service isn't bound yet
    // (PlatformException), there is by definition nothing holding the
    // camera on our side — treat that the same as "not busy" so scanning
    // still proceeds.
    var busy = false;
    try {
      await _cameraPlatform.stopPreview();
      final status = await _cameraPlatform.getStatus();
      busy = status.isPreviewReady;
    } on PlatformException catch (error) {
      debugPrint('camera release before QR scan failed: $error');
    } on MissingPluginException catch (error) {
      debugPrint('camera release before QR scan failed: $error');
    }
    if (mounted) setState(() => _cameraBusy = busy);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() => _processing = true);
    try {
      final payload = QrPairingPayload.fromJsonString(raw);
      debugPrint(
        'QR pairing payload: hosts=${payload.hosts} port=${payload.port} '
        'wsPath=${payload.wsPath} pcId=${payload.pcId} expiresAt=${payload.expiresAt}',
      );
      if (payload.isExpired) {
        _showError('This QR code has expired — ask the PC to show a new one.');
        return;
      }

      final result = await PcSignalingClient.pairOnce(PairingCandidate.fromQr(payload));
      await ref
          .read(pairedPcsProvider.notifier)
          .addFromPairing(
            pcId: result.pcId,
            displayName: result.pcName,
            // The address that won the race, not necessarily payload.host —
            // a multi-homed PC advertises several and only some are
            // routable from whichever network this phone is on.
            host: result.host,
            allHosts: payload.hosts,
            port: payload.port,
            wsPath: payload.wsPath,
            token: result.token,
          );

      if (mounted) Navigator.of(context).pop(true);
    } on FormatException {
      _showError('Invalid QR code.');
    } on PairingRejectedException catch (e) {
      _showError('Pairing rejected: ${e.errorCode}');
    } catch (e) {
      _showError('Could not pair: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    // Give the camera back to CameraPreviewPane regardless of how this page
    // is leaving (paired, cancelled, backed out of) — see the class doc
    // comment for why this is what un-freezes it. Skipped when the camera
    // was never actually released above (still busy/live-publishing): there
    // is nothing to give back, and re-issuing startPreview would just be a
    // redundant no-op re-attach.
    if (_cameraBusy == false) {
      unawaited(
        _cameraPlatform
            .startPreview(width: _resolution.width, height: _resolution.height)
            .catchError((Object error) {
              debugPrint('camera re-attach after QR scan failed: $error');
              return null;
            }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan PC pairing code')),
      body: switch (_cameraBusy) {
        null => const Center(child: CircularProgressIndicator()),
        true => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Text(
              "Can't scan while streaming from the camera — stop your stream "
              'first, then try again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        false => Stack(
          children: [
            MobileScanner(onDetect: _onDetect),
            if (_processing) const Center(child: CircularProgressIndicator()),
          ],
        ),
      },
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
