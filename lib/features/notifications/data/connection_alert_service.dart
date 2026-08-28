import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../streaming_engine/domain/publisher_event.dart';

/// Local notifications for a stream that has dropped (PLAN.md Phase 7).
///
/// The whole point is to reach the user when they *aren't* looking at the app
/// — Android keeps publishing in a foreground service while the phone is in a
/// pocket, so a silent failure could otherwise go unnoticed for a long time.
/// A snack bar cannot do that job.
class ConnectionAlertService {
  ConnectionAlertService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialised = false;

  /// Tracks what was last announced so a status that ticks every second
  /// doesn't post a notification every second.
  PublisherStatus? _lastAnnounced;

  static const _channelId = 'stream_alerts';
  static const _notificationId = 3;

  Future<void> initialize() async {
    if (_initialised) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // Reuses the launcher icon rather than shipping a second asset;
          // a missing drawable makes the notification silently fail to post.
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _initialised = true;
    } catch (error) {
      debugPrint('notification init failed: $error');
    }
  }

  /// Reacts to a publisher status change. Only transitions *into* a bad state
  /// are announced, and recovery quietly clears the notification rather than
  /// posting a second one.
  Future<void> onStatusChanged(PublisherEvent event) async {
    final status = event.status;
    if (status == _lastAnnounced) return;

    switch (status) {
      case PublisherStatus.error:
        _lastAnnounced = status;
        await _show(
          'Stream stopped',
          event.message ?? 'The connection to your destination was lost.',
        );
      case PublisherStatus.reconnecting:
        _lastAnnounced = status;
        await _show('Reconnecting', 'The stream dropped and is trying to reconnect.');
      case PublisherStatus.live:
        // Coming back up is only worth a notification if we had complained;
        // otherwise going live is not news.
        final wasBad = _lastAnnounced == PublisherStatus.reconnecting ||
            _lastAnnounced == PublisherStatus.error;
        _lastAnnounced = status;
        if (wasBad) await _cancel();
      case PublisherStatus.idle:
      case PublisherStatus.connecting:
      case PublisherStatus.stopped:
        _lastAnnounced = status;
        await _cancel();
    }
  }

  /// Forgets what was announced, so the next session starts clean.
  void reset() => _lastAnnounced = null;

  Future<void> _show(String title, String body) async {
    await initialize();
    if (!_initialised) return;
    try {
      await _plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Stream alerts',
            channelDescription: 'Tells you when a live stream drops.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      debugPrint('notification show failed: $error');
    }
  }

  Future<void> _cancel() async {
    if (!_initialised) return;
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (error) {
      debugPrint('notification cancel failed: $error');
    }
  }
}
