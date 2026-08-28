import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/stream_session_provider.dart';
import '../domain/paired_pc.dart';
import '../domain/pc_connection_status.dart';
import 'paired_pcs_provider.dart';

String _phaseLabel(PcConnectionPhase phase) => switch (phase) {
  PcConnectionPhase.idle => 'Not connected',
  PcConnectionPhase.connectingSignaling => 'Connecting…',
  PcConnectionPhase.pairing => 'Authenticating…',
  PcConnectionPhase.negotiating => 'Negotiating…',
  PcConnectionPhase.connected => 'Connected',
  PcConnectionPhase.reconnecting => 'Reconnecting…',
  PcConnectionPhase.error => 'Error',
  PcConnectionPhase.disconnected => 'Disconnected',
};

/// Entry point for Settings → PC Connection: lists paired PCs, offers "Pair
/// new PC" via QR scan or manual PIN entry, and connects/disconnects the
/// live session (`streamSessionProvider`) to a tapped PC.
class PairingScreen extends ConsumerWidget {
  const PairingScreen({super.key});

  Future<void> _pairNewPc(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner, color: Colors.white70),
              title: const Text('Scan QR code', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Shown on the PC you want to pair', style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/settings/pc-connection/scan');
              },
            ),
            ListTile(
              leading: const Icon(Icons.pin, color: Colors.white70),
              title: const Text('Enter PIN manually', style: TextStyle(color: Colors.white)),
              subtitle: const Text("If you can't scan a QR code", style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/settings/pc-connection/manual');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pcsAsync = ref.watch(pairedPcsProvider);
    final pcConnectionEvent = ref.watch(streamSessionProvider.select((s) => s.pcConnectionEvent));

    return Scaffold(
      appBar: AppBar(title: const Text('PC Connection')),
      body: pcsAsync.when(
        data: (pcs) => pcs.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No paired PCs yet. Pair one to start sending your stream to it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            : ListView(
                children: [
                  for (final pc in pcs) _PairedPcTile(pc: pc, connectionEvent: pcConnectionEvent),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load paired PCs: $e', style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pairNewPc(context),
        icon: const Icon(Icons.add),
        label: const Text('Pair new PC'),
      ),
    );
  }
}

class _PairedPcTile extends ConsumerWidget {
  const _PairedPcTile({required this.pc, required this.connectionEvent});

  final PairedPc pc;
  final PcConnectionEvent connectionEvent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThisPc = connectionEvent.pcId == pc.pcId;
    final phase = isThisPc ? connectionEvent.phase : PcConnectionPhase.idle;
    final isBusy = isThisPc &&
        (phase == PcConnectionPhase.connectingSignaling ||
            phase == PcConnectionPhase.pairing ||
            phase == PcConnectionPhase.negotiating);
    final isConnected = isThisPc && phase == PcConnectionPhase.connected;

    return ListTile(
      leading: const Icon(Icons.desktop_windows, color: Colors.white70),
      title: Text(pc.displayName, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        isThisPc ? _phaseLabel(phase) : '${pc.lastKnownHost}:${pc.lastKnownPort}',
        style: TextStyle(color: isConnected ? Colors.greenAccent : Colors.white54),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBusy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: () {
                final notifier = ref.read(streamSessionProvider.notifier);
                if (isConnected) {
                  notifier.disconnectFromPc();
                } else {
                  notifier.connectToPc(pc);
                }
              },
              child: Text(isConnected ? 'Disconnect' : 'Connect'),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
            onPressed: () => ref.read(pairedPcsProvider.notifier).remove(pc.pcId),
          ),
        ],
      ),
    );
  }
}
