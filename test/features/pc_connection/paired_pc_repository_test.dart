import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/secure_token_store.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/features/pc_connection/data/paired_pc_repository.dart';

class MockSecureTokenStore extends Mock implements SecureTokenStore {}

void main() {
  late MockSecureTokenStore secureStore;
  late SettingsRepository settings;
  late PairedPcRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.create();
    secureStore = MockSecureTokenStore();
    when(() => secureStore.write(any(), any())).thenAnswer((_) async {});
    when(() => secureStore.delete(any())).thenAnswer((_) async {});
    repository = PairedPcRepository(settings, secureStore);
  });

  test('starts empty', () {
    expect(repository.read(), isEmpty);
  });

  test('addFromPairing() persists a PC and stores its token securely', () async {
    final saved = await repository.addFromPairing(
      pcId: 'pc-1',
      displayName: "Alex's PC",
      host: '192.168.1.42',
      port: 58712,
      wsPath: '/pair',
      token: 'secret-token',
    );

    final reloaded = repository.read();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.pcId, 'pc-1');
    expect(reloaded.single.lastKnownHost, '192.168.1.42');
    verify(() => secureStore.write(saved.secureTokenId, 'secret-token')).called(1);
  });

  test('addFromPairing() with an already-known pcId replaces the record and reuses its token id', () async {
    final first = await repository.addFromPairing(
      pcId: 'pc-1',
      displayName: 'Old Name',
      host: '10.0.0.1',
      port: 1,
      wsPath: '/pair',
      token: 'old-token',
    );

    final second = await repository.addFromPairing(
      pcId: 'pc-1',
      displayName: 'New Name',
      host: '10.0.0.2',
      port: 2,
      wsPath: '/pair',
      token: 'new-token',
    );

    expect(repository.read(), hasLength(1));
    expect(repository.read().single.displayName, 'New Name');
    expect(second.secureTokenId, first.secureTokenId);
    verify(() => secureStore.write(first.secureTokenId, 'new-token')).called(1);
  });

  test('remove() deletes both the PC and its secure token', () async {
    final saved = await repository.addFromPairing(
      pcId: 'pc-1',
      displayName: 'A PC',
      host: '10.0.0.1',
      port: 1,
      wsPath: '/pair',
      token: 'tok',
    );

    await repository.remove(saved.pcId);

    expect(repository.read(), isEmpty);
    verify(() => secureStore.delete(saved.secureTokenId)).called(1);
  });

  test('updateLastKnownAddress() updates just the targeted PC', () async {
    final a = await repository.addFromPairing(
      pcId: 'pc-a',
      displayName: 'A',
      host: '10.0.0.1',
      port: 1,
      wsPath: '/pair',
      token: 'ta',
    );
    await repository.addFromPairing(
      pcId: 'pc-b',
      displayName: 'B',
      host: '10.0.0.2',
      port: 2,
      wsPath: '/pair',
      token: 'tb',
    );

    await repository.updateLastKnownAddress(a.pcId, host: '10.0.0.99', port: 99);

    final result = {for (final p in repository.read()) p.pcId: p};
    expect(result['pc-a']!.lastKnownHost, '10.0.0.99');
    expect(result['pc-a']!.lastKnownPort, 99);
    expect(result['pc-b']!.lastKnownHost, '10.0.0.2');
  });
}
