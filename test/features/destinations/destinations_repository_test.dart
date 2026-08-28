import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/secure_token_store.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/features/destinations/data/destinations_repository.dart';
import 'package:stream_phone_cam/features/destinations/domain/stream_destination.dart';

class MockSecureTokenStore extends Mock implements SecureTokenStore {}

void main() {
  late MockSecureTokenStore secureStore;
  late SettingsRepository settings;
  late DestinationsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.create();
    secureStore = MockSecureTokenStore();
    when(() => secureStore.write(any(), any())).thenAnswer((_) async {});
    when(() => secureStore.delete(any())).thenAnswer((_) async {});
    repository = DestinationsRepository(settings, secureStore);
  });

  test('starts empty', () {
    expect(repository.read(), isEmpty);
  });

  test('add() persists a destination and stores its key securely', () async {
    final saved = await repository.add(
      platform: StreamPlatform.custom,
      displayName: 'My RTMP',
      rtmpUrl: 'rtmp://example.com/live',
      streamKey: 'secret-key',
    );

    final reloaded = repository.read();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.id, saved.id);
    expect(reloaded.single.displayName, 'My RTMP');
    expect(reloaded.single.rtmpUrl, 'rtmp://example.com/live');
    verify(() => secureStore.write(saved.secureKeyId, 'secret-key')).called(1);
  });

  test('remove() deletes both the destination and its secure key', () async {
    final saved = await repository.add(
      platform: StreamPlatform.twitch,
      displayName: 'Twitch',
      rtmpUrl: 'rtmp://live.twitch.tv/app',
      streamKey: 'twitch-key',
    );

    await repository.remove(saved.id);

    expect(repository.read(), isEmpty);
    verify(() => secureStore.delete(saved.secureKeyId)).called(1);
  });

  test('setEnabled() toggles just the targeted destination', () async {
    final a = await repository.add(
      platform: StreamPlatform.custom,
      displayName: 'A',
      rtmpUrl: 'rtmp://a',
      streamKey: 'ka',
    );
    final b = await repository.add(
      platform: StreamPlatform.custom,
      displayName: 'B',
      rtmpUrl: 'rtmp://b',
      streamKey: 'kb',
    );

    await repository.setEnabled(a.id, false);

    final result = {for (final d in repository.read()) d.id: d.enabled};
    expect(result[a.id], isFalse);
    expect(result[b.id], isTrue);
  });
}
