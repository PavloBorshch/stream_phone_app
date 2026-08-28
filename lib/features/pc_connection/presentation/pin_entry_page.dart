import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pc_signaling_client.dart';
import '../domain/discovered_pc.dart';
import '../domain/pairing_session.dart';
import 'lan_discovery_provider.dart';
import 'paired_pcs_provider.dart';

/// Fallback pairing path when scanning a QR isn't possible: pick a
/// LAN-discovered PC (or type its host manually) and enter the PIN shown
/// on its screen. See HELP.md's "PIN fallback" section.
class PinEntryPage extends ConsumerStatefulWidget {
  const PinEntryPage({super.key});

  @override
  ConsumerState<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends ConsumerState<PinEntryPage> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '58712');
  final _pinController = TextEditingController();
  bool _pairing = false;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _selectDiscovered(DiscoveredPc pc) {
    setState(() {
      _hostController.text = pc.host;
      _portController.text = pc.port.toString();
    });
  }

  Future<void> _pair() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _pairing = true);
    try {
      final candidate = PairingCandidate.fromManualEntry(
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        pin: _pinController.text.trim(),
      );
      debugPrint('PIN pairing candidate: host=${candidate.host} port=${candidate.port} wsPath=${candidate.wsPath}');
      final result = await PcSignalingClient.pairOnce(candidate);
      await ref
          .read(pairedPcsProvider.notifier)
          .addFromPairing(
            pcId: result.pcId,
            displayName: result.pcName,
            host: result.host,
            allHosts: candidate.hosts,
            port: candidate.port,
            wsPath: candidate.wsPath,
            token: result.token,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on PairingRejectedException catch (e) {
      _showError('Pairing rejected: ${e.errorCode}');
    } catch (e) {
      _showError('Could not pair: $e');
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final discovered = ref.watch(lanDiscoveryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Enter pairing PIN')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (discovered.isNotEmpty) ...[
            const Text('NEARBY PCS', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            for (final pc in discovered)
              ListTile(
                leading: const Icon(Icons.desktop_windows, color: Colors.white70),
                title: Text(pc.pcName, style: const TextStyle(color: Colors.white)),
                subtitle: Text('${pc.host}:${pc.port}', style: const TextStyle(color: Colors.white54)),
                onTap: () => _selectDiscovered(pc),
              ),
            const Divider(height: 32, color: Colors.white12),
          ],
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _hostController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'PC host / IP address'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Port'),
                  validator: (v) => (int.tryParse(v?.trim() ?? '') == null) ? 'Enter a valid port' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'PIN shown on PC'),
                  validator: (v) => (v == null || v.trim().length != 6) ? 'Enter the 6-digit PIN' : null,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _pairing ? null : _pair,
                  child: _pairing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Pair'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
