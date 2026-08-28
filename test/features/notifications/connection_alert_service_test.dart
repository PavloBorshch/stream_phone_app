import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stream_phone_cam/features/notifications/data/connection_alert_service.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publisher_event.dart';

class MockNotificationsPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _FakeInitializationSettings extends Fake implements InitializationSettings {}

class _FakeNotificationDetails extends Fake implements NotificationDetails {}

void main() {
  late MockNotificationsPlugin plugin;
  late ConnectionAlertService service;

  setUpAll(() {
    registerFallbackValue(_FakeInitializationSettings());
    registerFallbackValue(_FakeNotificationDetails());
  });

  setUp(() {
    plugin = MockNotificationsPlugin();
    when(() => plugin.initialize(settings: any(named: 'settings'))).thenAnswer((_) async => true);
    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).thenAnswer((_) async {});
    when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
    service = ConnectionAlertService(plugin);
  });

  Future<void> feed(List<PublisherStatus> statuses, {String? message}) async {
    for (final status in statuses) {
      await service.onStatusChanged(PublisherEvent(status: status, message: message));
    }
  }

  test('announces an error with its message', () async {
    await feed([PublisherStatus.live, PublisherStatus.error], message: 'Ingest refused');

    verify(
      () => plugin.show(
        id: any(named: 'id'),
        title: 'Stream stopped',
        body: 'Ingest refused',
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
  });

  test('announces a reconnect', () async {
    await feed([PublisherStatus.live, PublisherStatus.reconnecting]);

    verify(
      () => plugin.show(
        id: any(named: 'id'),
        title: 'Reconnecting',
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
  });

  test('a repeated status does not post a second notification', () async {
    // Publisher stats tick every second; announcing each tick would be a
    // stream of identical notifications.
    await feed([
      PublisherStatus.live,
      PublisherStatus.reconnecting,
      PublisherStatus.reconnecting,
      PublisherStatus.reconnecting,
    ]);

    verify(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
  });

  test('recovering clears the notification instead of posting another', () async {
    await feed([PublisherStatus.live, PublisherStatus.reconnecting, PublisherStatus.live]);

    verify(() => plugin.cancel(id: any(named: 'id'))).called(1);
    verifyNever(
      () => plugin.show(
        id: any(named: 'id'),
        title: 'Stream stopped',
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    );
  });

  test('going live without a prior problem is not news', () async {
    await feed([PublisherStatus.connecting, PublisherStatus.live]);

    verifyNever(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    );
  });

  test('reset lets the next session announce the same status again', () async {
    await feed([PublisherStatus.live, PublisherStatus.error]);
    service.reset();
    await feed([PublisherStatus.error]);

    verify(
      () => plugin.show(
        id: any(named: 'id'),
        title: 'Stream stopped',
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(2);
  });

  test('a plugin that throws never breaks the caller', () async {
    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).thenThrow(Exception('no notification channel'));

    // A failed notification must never take down a live stream.
    await expectLater(
      service.onStatusChanged(const PublisherEvent(status: PublisherStatus.error)),
      completes,
    );
  });
}
