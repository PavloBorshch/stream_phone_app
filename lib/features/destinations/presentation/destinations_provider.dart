import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/secure_token_store_provider.dart';
import '../../../core/persistence/settings_repository_provider.dart';
import '../../video_settings/domain/video_overrides.dart';
import '../data/destinations_repository.dart';
import '../data/oauth/kick_oauth_client.dart';
import '../data/oauth/twitch_oauth_client.dart';
import '../domain/stream_destination.dart';

final destinationsRepositoryProvider = Provider<DestinationsRepository>((ref) {
  return DestinationsRepository(ref.watch(settingsRepositoryProvider), ref.watch(secureTokenStoreProvider));
});

final twitchOAuthClientProvider = Provider<TwitchOAuthClient>((ref) => TwitchOAuthClient());
final kickOAuthClientProvider = Provider<KickOAuthClient>((ref) => KickOAuthClient());

class DestinationsNotifier extends Notifier<AsyncValue<List<StreamDestination>>> {
  @override
  AsyncValue<List<StreamDestination>> build() {
    return AsyncValue.data(ref.watch(destinationsRepositoryProvider).read());
  }

  Future<void> _reload() async {
    state = AsyncValue.data(ref.read(destinationsRepositoryProvider).read());
  }

  Future<void> addCustom({
    required String displayName,
    required String rtmpUrl,
    required String streamKey,
  }) async {
    await ref
        .read(destinationsRepositoryProvider)
        .add(platform: StreamPlatform.custom, displayName: displayName, rtmpUrl: rtmpUrl, streamKey: streamKey);
    await _reload();
  }

  /// Opens Twitch's login/consent screen and, on success, saves a Twitch
  /// destination pre-filled with the fetched stream key.
  Future<void> linkTwitch() async {
    final result = await ref.read(twitchOAuthClientProvider).link();
    await ref
        .read(destinationsRepositoryProvider)
        .add(
          platform: StreamPlatform.twitch,
          displayName: 'Twitch — ${result.loginName}',
          rtmpUrl: 'rtmp://live.twitch.tv/app',
          streamKey: result.streamKey,
        );
    await _reload();
  }

  /// Always throws [KickBackendRequiredException] today — see
  /// [KickOAuthClient]'s doc comment. Kept as its own method (rather than
  /// hidden behind a disabled button) so the UI can show the real reason.
  Future<void> linkKick() async {
    await ref.read(kickOAuthClientProvider).link();
  }

  Future<void> remove(String id) async {
    await ref.read(destinationsRepositoryProvider).remove(id);
    await _reload();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await ref.read(destinationsRepositoryProvider).setEnabled(id, enabled);
    await _reload();
  }

  Future<void> setOverrides(String id, VideoOverrides overrides) async {
    await ref.read(destinationsRepositoryProvider).setOverrides(id, overrides);
    await _reload();
  }
}

final destinationsProvider = NotifierProvider<DestinationsNotifier, AsyncValue<List<StreamDestination>>>(
  DestinationsNotifier.new,
);
