# Local patch notes — flutter_webrtc 1.6.0

This is a vendored copy of `flutter_webrtc` 1.6.0 from pub.dev
(`third_party` and desktop-only platform folders removed — this app only
targets Android/iOS), wired in via `dependency_overrides` in the root
`pubspec.yaml`. It exists for one reason: PLAN.md's "Leg A" (streaming the
composited camera/screencast frame to a paired PC over the existing WebRTC
data connection) needs to attach a `MediaStreamTrack` that native Android
code built directly against `PeerConnectionFactory` (fed from HaishinKit's
`MediaMixer`, not from `getUserMedia`) to a peer connection the Dart side
already created via the normal `createPeerConnection()` call. Stock
flutter_webrtc has no public API for that — see HELP.md §8's "Leg A media
track" section for the protocol this enables.

## Exactly what changed vs. upstream 1.6.0

1. `lib/src/native/rtc_peerconnection_impl.dart` — added a public
   `peerConnectionId` getter on `RTCPeerConnectionNative` (was
   library-private `_peerConnectionId`). Needed so Dart-side app code
   (`PcConnectionPlatform.peerConnectionId`) can hand this id down to
   native code through a normal platform-channel call.
2. `android/.../FlutterWebRTCPlugin.java` — added
   `attachExternalTrack(peerConnectionId, track)` /
   `detachExternalTrack(peerConnectionId, track)`, both public passthroughs
   to (3), following the exact style of the existing
   `getPeerConnectionFactory()` passthrough already in this file.
3. `android/.../MethodCallHandlerImpl.java` — added the actual
   `attachExternalTrack`/`detachExternalTrack` implementations: look up the
   `PeerConnectionObserver` for the given id (the same private
   `mPeerConnectionObservers` map every stock method already uses), register
   the track in `localTracks` the same way a `getUserMedia` track would be
   (so it's not invisible to any future Dart-side track lookup), then call
   the real `PeerConnection.addTrack`/`removeTrack`.

No other files were touched. No iOS patch exists yet — Leg A is Android-only
so far, matching PLAN.md's existing Android/iOS split for the rest of the
publisher.

`attachExternalTrack`/`detachExternalTrack` are track-kind-agnostic (they
already branch on `track.kind()` into `LocalVideoTrack`/`LocalAudioTrack`),
so Leg A's audio track (added 2026-08-26, `PublisherForegroundService
.attachWebRtcAudio` — a second, independent microphone capture; see
PLAN.md's Phase 5 note for why it isn't fed from the same mixer the video
track is) reuses this same patch unchanged.

## Upgrading this vendored copy

To pick up a newer flutter_webrtc release: copy the new version's `lib/`,
`android/`, `ios/`, `assets/`, `pubspec.yaml`, `LICENSE`, `CHANGELOG.md` over
this directory, then re-apply the three edits above (diff against a fresh
1.6.0 checkout from pub.dev if useful — none of the three touch code likely
to have moved much, but check line numbers/method bodies weren't
restructured). Re-run `flutter analyze` and `flutter build apk --debug`
afterward.

## Why vendoring instead of a reflection-based hack

The alternative — reaching into `FlutterWebRTCPlugin`'s private
`methodCallHandler` field via reflection from app code — was considered and
rejected: it's fragile (breaks silently on any field rename, no compiler
check), and every other piece this patch touches (`PeerConnectionObserver`,
`getPeerConnectionObserver`, `PeerConnection.addTrack`) is otherwise
perfectly reachable through normal, compiler-checked Java once the one
missing public entry point exists. Three small, readable, diffable patches
beat a reflective workaround.
