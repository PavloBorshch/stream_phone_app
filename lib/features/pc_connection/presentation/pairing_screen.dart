import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/stream_session_provider.dart';
import '../domain/discovered_pc.dart';
import '../domain/paired_pc.dart';
import '../domain/pc_connection_status.dart';
import 'paired_pcs_provider.dart';
import 'usb_discovery_provider.dart';
import 'usb_transport_preference.dart';

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

    final usb = ref.watch(usbDiscoveryProvider);
    final pairedIds = (pcsAsync.valueOrNull ?? const <PairedPc>[])
        .map((pc) => pc.pcId)
        .toSet();
    final unpairedUsbPc =
        (usb.pc != null && !pairedIds.contains(usb.pc!.pcId)) ? usb.pc : null;

    return Scaffold(
      appBar: AppBar(title: const Text('PC Connection')),
      body: pcsAsync.when(
        data: (pcs) => ListView(
          children: [
            const _PreferUsbSwitch(),
            const Divider(height: 1),
            // Shown above the paired list, not inside the "no PCs yet"
            // empty state: a cable plugged in while PCs are already paired
            // is just as worth surfacing, and this is the screen the error
            // message sends people to.
            if (unpairedUsbPc != null)
              _UnpairedUsbPcTile(pc: unpairedUsbPc, onPair: () => _pairNewPc(context)),
            if (pcs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No paired PCs yet. Pair one to start sending your stream to it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            for (final pc in pcs)
              _PairedPcTile(pc: pc, connectionEvent: pcConnectionEvent),
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

/// A PC found on the USB tunnel that this phone has never paired with.
///
/// Being reachable over a cable is not authorisation, so this cannot just
/// connect — pairing still needs the PIN shown on the PC. What it removes
/// is the hunting: without it the only place a USB-connected PC appeared
/// was inside the manual-PIN screen, four taps deep, which is not where
/// anyone looks after plugging in a cable and being told no PC is
/// connected.
class _UnpairedUsbPcTile extends StatelessWidget {
  const _UnpairedUsbPcTile({required this.pc, required this.onPair});

  final DiscoveredPc pc;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: ListTile(
        leading: const Icon(Icons.usb, color: Colors.greenAccent),
        title: Text(pc.pcName, style: const TextStyle(color: Colors.white)),
        subtitle: const Text(
          'Connected by cable, not paired yet',
          style: TextStyle(color: Colors.white54),
        ),
        trailing: FilledButton(onPressed: onPair, child: const Text('Pair')),
      ),
    );
  }
}

/// Chooses which link carries the stream when both are available.
///
/// Needed because "a cable is plugged in" does not mean "use the cable" —
/// in this app the phone is very often plugged in just to charge while
/// streaming, and picking the transport by whether a cable happens to be
/// present would quietly trade latency away every time.
class _PreferUsbSwitch extends ConsumerWidget {
  const _PreferUsbSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferUsb = ref.watch(preferUsbTransportProvider);
    return SwitchListTile(
      value: preferUsb,
      onChanged: (value) =>
          ref.read(preferUsbTransportProvider.notifier).set(value),
      secondary: Icon(
        preferUsb ? Icons.usb : Icons.wifi,
        color: Colors.white70,
      ),
      title: const Text(
        'Stream over USB when connected',
        style: TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        preferUsb
            ? 'Uses the cable whenever one is available — works with Wi-Fi '
                  'off, but adds some delay.'
            : 'Always uses the network. Lower delay, but needs Wi-Fi.',
        style: const TextStyle(color: Colors.white54),
      ),
    );
  }
}
