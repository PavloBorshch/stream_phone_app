import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/pc_signaling_client.dart';
import '../domain/pairing_session.dart';
import 'paired_pcs_provider.dart';

/// Scans the QR code the PC client displays (see HELP.md's "QR payload"
/// section). This app only ever scans — it never generates/displays a QR
/// itself, per PLAN.md's Phase 4 pairing-direction decision.
class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});

  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage> {
  bool _processing = false;

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan PC pairing code')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          if (_processing) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
