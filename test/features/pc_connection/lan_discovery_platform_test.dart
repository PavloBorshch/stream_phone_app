import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/pc_connection/data/lan_discovery_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('com.streamphonecam/lan_discovery');
  const eventChannel = EventChannel('com.streamphonecam/lan_discovery_events');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late LanDiscoveryPlatform platform;
  final calledMethods = <String>[];

  setUp(() {
    calledMethods.clear();
    platform = LanDiscoveryPlatform();
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calledMethods.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test('startBrowse/stopBrowse invoke the matching native methods', () async {
    await platform.startBrowse();
    await platform.stopBrowse();
    expect(calledMethods, ['startBrowse', 'stopBrowse']);
  });

  test('events() decodes found/lost/browseError payloads', () async {
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) => sink = events),
    );

    final received = <LanDiscoveryEvent>[];
    final subscription = platform.events().listen(received.add);
    await Future<void>.delayed(Duration.zero);

    sink.success({
      'type': 'found',
      'pcId': 'pc-1',
      'pcName': "Alex's PC",
      'host': '192.168.1.42',
      'port': 58712,
      'wsPath': '/pair',
    });
    sink.success({
      'type': 'lost',
      'pcId': 'pc-1',
      'pcName': "Alex's PC",
      'host': '192.168.1.42',
      'port': 58712,
      'wsPath': '/pair',
    });
    sink.success({'type': 'browseError', 'message': 'NSD failure'});
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(3));
    expect(received[0].type, LanDiscoveryEventType.found);
    expect(received[0].pc?.pcId, 'pc-1');
    expect(received[1].type, LanDiscoveryEventType.lost);
    expect(received[2].type, LanDiscoveryEventType.browseError);
    expect(received[2].message, 'NSD failure');

    await subscription.cancel();
  });
}
