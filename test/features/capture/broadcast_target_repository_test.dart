import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/features/capture/data/broadcast_target_repository.dart';
import 'package:stream_phone_cam/features/capture/domain/broadcast_target.dart';
import 'package:stream_phone_cam/features/capture/presentation/broadcast_target_provider.dart';

void main() {
  late SettingsRepository settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.create();
  });

  test('repository reads toServices when nothing is stored', () {
    expect(BroadcastTargetRepository(settings).read(), BroadcastTarget.toServices);
  });

  test('repository round-trips every value', () async {
    final repository = BroadcastTargetRepository(settings);

    for (final value in BroadcastTarget.values) {
      await repository.write(value);
      expect(repository.read(), value);
    }
  });

  test('provider reads through to the underlying settings repository', () async {
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    await container.read(broadcastTargetRepositoryProvider).write(BroadcastTarget.both);

    final reopened = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    addTearDown(reopened.dispose);

    expect(reopened.read(broadcastTargetRepositoryProvider).read(), BroadcastTarget.both);
  });
}
