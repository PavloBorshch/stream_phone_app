import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/stream_session_provider.dart';
import '../../streaming_engine/domain/publisher_event.dart';

/// Expandable stream-health panel (PLAN.md Phase 7).
///
/// Collapsed by default: it sits over the viewfinder, and the status pill
/// already carries the headline numbers. Expanded, it breaks the session down
/// per destination, which is the only place a single failing leg of a
/// multistream is visible.
class StreamStatsOverlay extends ConsumerStatefulWidget {
  const StreamStatsOverlay({super.key});

  @override
  ConsumerState<StreamStatsOverlay> createState() => _StreamStatsOverlayState();
}

class _StreamStatsOverlayState extends ConsumerState<StreamStatsOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final publisher = ref.watch(streamSessionProvider.select((state) => state.publisherEvent));
    if (!publisher.isActive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insights, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  _headline(publisher),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(color: Colors.white24, height: 12),
            _statRow('Uptime', _formatUptime(publisher.uptimeSeconds)),
            _statRow('Sent', _formatBytes(publisher.bytesSent)),
            _statRow(
              'Bitrate',
              publisher.bitrateKbps == null
                  ? '—'
                  // Measured against target is the pair that explains *why*
                  // quality dropped; either number alone doesn't.
                  : '${publisher.bitrateKbps} kbps'
                      '${publisher.targetBitrateKbps == null ? '' : ' of ${publisher.targetBitrateKbps}'}',
            ),
            _statRow('Frame rate', publisher.fps == null ? '—' : '${publisher.fps} fps'),
            _statRow('Dropped', '${publisher.droppedFrames ?? 0}'),
            if (publisher.destinations.isNotEmpty) ...[
              const Divider(color: Colors.white24, height: 12),
              for (final destination in publisher.destinations)
                _statRow(
                  destination.destinationId,
                  _destinationSummary(destination),
                  valueColor: destination.status == PublisherStatus.error
                      ? Colors.redAccent
                      : Colors.white70,
                ),
            ],
          ],
        ],
      ),
    );
  }

  String _headline(PublisherEvent publisher) {
    final live = publisher.destinations.where((d) => d.status == PublisherStatus.live).length;
    final total = publisher.destinations.length;
    if (total == 0) return 'Stats';
    return '$live/$total live';
  }

  String _destinationSummary(DestinationPublishState destination) {
    if (destination.status == PublisherStatus.error) return 'error';
    final parts = <String>[
      destination.status.name,
      if (destination.targetBitrateKbps != null) '${destination.targetBitrateKbps} kbps',
      if (destination.rttMs != null) '${destination.rttMs} ms',
    ];
    return parts.join(' · ');
  }

  Widget _statRow(String label, String value, {Color valueColor = Colors.white70}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Text(value, style: TextStyle(color: valueColor, fontSize: 11)),
        ],
      ),
    );
  }

  static String _formatUptime(int? seconds) {
    if (seconds == null) return '—';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  static String _formatBytes(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
