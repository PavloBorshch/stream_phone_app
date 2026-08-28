import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/oauth/kick_oauth_client.dart';
import '../domain/stream_destination.dart';
import 'destinations_provider.dart';
import 'widgets/custom_rtmp_form.dart';
import 'widgets/platform_link_tile.dart';

class DestinationsScreen extends ConsumerStatefulWidget {
  const DestinationsScreen({super.key});

  @override
  ConsumerState<DestinationsScreen> createState() => _DestinationsScreenState();
}

class _DestinationsScreenState extends ConsumerState<DestinationsScreen> {
  StreamPlatform? _linking;

  Future<void> _linkTwitch() async {
    setState(() => _linking = StreamPlatform.twitch);
    try {
      await ref.read(destinationsProvider.notifier).linkTwitch();
    } catch (e) {
      _showError('Twitch', e);
    } finally {
      if (mounted) setState(() => _linking = null);
    }
  }

  Future<void> _linkKick() async {
    setState(() => _linking = StreamPlatform.kick);
    try {
      await ref.read(destinationsProvider.notifier).linkKick();
    } on KickBackendRequiredException catch (e) {
      _showError('Kick', e, isExpected: true);
    } catch (e) {
      _showError('Kick', e);
    } finally {
      if (mounted) setState(() => _linking = null);
    }
  }

  void _showError(String platform, Object error, {bool isExpected = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isExpected ? '$error' : "Couldn't connect $platform: $error"),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinationsAsync = ref.watch(destinationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Destinations & Accounts')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('CONNECT AN ACCOUNT', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          PlatformLinkTile(
            icon: Icons.videocam,
            title: 'Twitch',
            subtitle: 'Fetches your stream key automatically',
            isLinking: _linking == StreamPlatform.twitch,
            onTap: _linkTwitch,
          ),
          PlatformLinkTile(
            icon: Icons.videocam,
            title: 'Kick',
            subtitle: 'Not available yet — use Custom RTMP below',
            isLinking: _linking == StreamPlatform.kick,
            onTap: _linkKick,
          ),
          const Divider(height: 32, color: Colors.white12),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('YOUR DESTINATIONS', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          destinationsAsync.when(
            data: (destinations) => destinations.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('No destinations yet.', style: TextStyle(color: Colors.white54)),
                  )
                : Column(
                    children: [
                      for (final destination in destinations)
                        ListTile(
                          title: Text(destination.displayName, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(destination.rtmpUrl, style: const TextStyle(color: Colors.white54)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: destination.enabled,
                                onChanged: (v) =>
                                    ref.read(destinationsProvider.notifier).setEnabled(destination.id, v),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white54),
                                onPressed: () => ref.read(destinationsProvider.notifier).remove(destination.id),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load destinations: $e', style: const TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCustomRtmpForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Custom RTMP'),
      ),
    );
  }
}
