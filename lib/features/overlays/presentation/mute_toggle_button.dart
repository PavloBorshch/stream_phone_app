import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/stream_session_provider.dart';

/// Quick mic mute (PLAN.md Phase 7).
///
/// Mutes the encoder's audio input rather than stopping it: the audio track
/// keeps flowing as silence, so the ingest never sees a gap it would have to
/// resynchronise around. That distinction lives natively in
/// `CameraEncodeSession.setMuted`; this is only the control.
class MuteToggleButton extends ConsumerWidget {
  const MuteToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMuted = ref.watch(streamSessionProvider.select((state) => state.isMuted));

    return IconButton(
      tooltip: isMuted ? 'Unmute microphone' : 'Mute microphone',
      onPressed: () => ref.read(streamSessionProvider.notifier).setMuted(!isMuted),
      icon: Icon(
        isMuted ? Icons.mic_off : Icons.mic,
        // Muted is the state worth noticing — streaming silently by accident
        // is a mistake that can run for a long time before anyone says so.
        color: isMuted ? Colors.redAccent : Colors.white,
        size: 28,
      ),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black54,
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}
