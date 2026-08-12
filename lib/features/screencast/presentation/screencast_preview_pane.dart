import 'dart:io';

import 'package:flutter/material.dart';
import '../domain/screencast_status.dart';

/// Renders the Screencast capture surface. On Android this shows a live
/// [Texture] preview of the mirrored screen once capturing starts (the same
/// mechanism the `camera` plugin itself uses). On iOS, a live in-app preview
/// isn't possible - system-wide capture runs in a separate Broadcast Upload
/// Extension process that can't hand frames back to this app - so only a
/// status card is shown, driven by App Group state relayed over an
/// EventChannel.
///
/// Capture itself is owned natively (an Android foreground service /
/// iOS broadcast extension) and keeps running independent of this widget -
/// it is only stopped by an explicit user action, never by this pane
/// unmounting, so switching modes or closing and reopening the app doesn't
/// interrupt an in-progress screencast.
class ScreencastPreviewPane extends StatelessWidget {
  const ScreencastPreviewPane({super.key, required this.event});

  final ScreencastEvent event;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid && event.status == ScreencastStatus.capturing && event.textureId != null) {
      return Texture(textureId: event.textureId!);
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(event.status), color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                _messageFor(event),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(ScreencastStatus status) {
    switch (status) {
      case ScreencastStatus.capturing:
      case ScreencastStatus.paused:
        return Icons.screen_share;
      case ScreencastStatus.denied:
      case ScreencastStatus.error:
        return Icons.error_outline;
      default:
        return Icons.screen_share_outlined;
    }
  }

  String _messageFor(ScreencastEvent event) {
    if (event.message != null) return event.message!;
    switch (event.status) {
      case ScreencastStatus.idle:
        return Platform.isIOS
            ? 'Tap the broadcast button below to start screen capture'
            : 'Tap record to start screen capture';
      case ScreencastStatus.requesting:
        return 'Requesting screen capture permission...';
      case ScreencastStatus.starting:
        return 'Starting screen capture...';
      case ScreencastStatus.capturing:
        final frames = event.frameCount;
        return frames != null ? 'Screen capture active - $frames frames captured' : 'Screen capture active';
      case ScreencastStatus.paused:
        return 'Screen capture paused';
      case ScreencastStatus.stopped:
        return 'Screen capture stopped';
      case ScreencastStatus.denied:
        return 'Screen capture permission denied';
      case ScreencastStatus.error:
        return 'Screen capture error';
    }
  }
}
