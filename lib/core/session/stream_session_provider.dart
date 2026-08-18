import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/capture/domain/capture_mode.dart';
import '../../features/screencast/data/screencast_platform.dart';
import 'stream_session_state.dart';

final screencastPlatformProvider = Provider<ScreencastPlatform>((ref) => ScreencastPlatform());

class StreamSessionNotifier extends Notifier<StreamSessionState> {
  @override
  StreamSessionState build() {
    final platform = ref.watch(screencastPlatformProvider);

    final subscription = platform.events().listen((event) {
      state = state.copyWith(screencastEvent: event);
    });
    ref.onDispose(subscription.cancel);

    // Picks up a screencast that's still running natively from before this
    // provider existed (e.g. the app was closed and reopened while
    // broadcasting) - the event stream alone would otherwise stay silent
    // until the native side next has something new to report.
    platform.getStatus().then((event) {
      state = state.copyWith(screencastEvent: event);
    });

    return StreamSessionState.initial;
  }

  void setMode(CaptureMode mode) {
    if (mode == state.mode) return;
    // Deliberately leaves screencastEvent untouched: an in-progress
    // screencast keeps broadcasting in the background when switching to
    // Camera mode, so its status shouldn't be reset to idle here.
    state = state.copyWith(mode: mode);
  }
}

final streamSessionProvider = NotifierProvider<StreamSessionNotifier, StreamSessionState>(
  StreamSessionNotifier.new,
);
