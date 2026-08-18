# PLAN.md — Streaming Platform, PC Pairing & Settings Roadmap

## Overview

This plan turns StreamPhoneCam from a two-screen capture stub (Camera/Screencast preview with a stubbed "start stream" action and a stubbed settings icon) into a fully-configurable multistreaming app: a Settings page with connected platform accounts, custom RTMP/RTMPS/SRT destinations, multistreaming, a paired desktop-client transport, configurable video/audio, network resilience, on-screen overlays, battery/thermal handling, and connection-lost notifications.

It is organized as: **foundational architectural decisions** that everything else depends on, then **7 sequential phases**, then a **risk appendix** covering the hardest parts. Phases build on each other in order — later phases assume earlier ones are done.

## Current state summary

(Verified directly against the repo, not assumed.)

- Dependencies: only `camera: ^0.12.0+2` (runtime) and `flutter_lints` (dev). No state-management, persistence, routing, or networking package exists.
- Exactly one screen: `CaptureScreen` (`lib/features/capture/presentation/capture_screen.dart`), a plain `StatefulWidget` using `setState` — holds `CaptureMode` and the latest `ScreencastEvent` as local fields. No router exists (`MaterialApp(home: CaptureScreen())`, zero `Navigator.push` calls).
- The settings gear icon's `onPressed` is `debugPrint('Open settings')`; the Camera-mode record button's action is `debugPrint('Start stream')`. Screencast mode only reaches a local "capturing" state — no frames are sent anywhere yet.
- `camera_preview_pane.dart` hardcodes `ResolutionPreset.high` and `enableAudio: true` — no fps/bitrate/codec configuration exists.
- The `screencast` feature establishes the native-bridge pattern every new native feature should mirror: one `MethodChannel('com.streamphonecam/<feature>')` for imperative calls + one paired `EventChannel('com.streamphonecam/<feature>_events')` for a continuous status stream, decoded into a typed Dart domain object. Dart subscribes in `initState`, also calls a one-shot status getter to cover the race where native state predates the Dart subscription, and cancels in `dispose`.
- Android native capture (`ScreenCaptureForegroundService.kt`) is a foreground `Service` that owns the capture object independent of the Activity/engine lifecycle (`stopWithTask="false"`), bound by `MainActivity.kt`.
- iOS screen capture requires a separate Broadcast Upload Extension process (target not yet created in Xcode) relayed via App Group + Darwin notification, since iOS forbids in-process system-wide capture.
- No persistence mechanism of any kind exists yet (no `shared_preferences`/`hive`/etc.).
- No networking code exists yet (no `http`/`dio`/websocket/webrtc/rtmp/srt).
- Only test: one widget test (`test/features/capture/capture_mode_toggle_test.dart`) using plain `flutter_test`.

---

## 1. Foundational architectural decisions

These must be settled before Phase 2, because nearly every later feature touches them.

### 1.1 State management — Riverpod

A Settings screen needs to read/react to "is a stream live, to which destinations, at what bitrate" — the same session state the capture screen's record button and status pill need — plus half a dozen independent settings domains that must combine into one coherent session without wiring callbacks through many widget layers.

**Decision: `flutter_riverpod`.** Feature-scoped providers map cleanly onto the existing `lib/features/<feature>/` structure. `StreamNotifier`/`StreamProvider` map directly onto the existing `EventChannel.receiveBroadcastStream()` pattern (`ScreencastPlatform.events()`), so migrating is mostly relocating subscription logic rather than rewriting it. No `BuildContext` coupling is needed for services reachable from multiple screens (destinations repository, PC connection service). Testable via `ProviderContainer` without a widget tree.

Action: wrap `runApp` with `ProviderScope`; add `lib/core/session/stream_session_state.dart` + `stream_session_provider.dart` aggregating "current mode, active destinations, live/paused/idle, aggregate stats" as the one shared cross-cutting state both `CaptureScreen` and the new `SettingsScreen` read.

### 1.2 Persistence — split by sensitivity

Needed: settings objects (video/audio/network/on-screen/battery), destination list + per-destination overrides, last-used destination, PC pairing records, OAuth tokens.

**Decision:**
- `shared_preferences` for structured, non-sensitive config — one JSON blob per domain (`video_settings`, `audio_settings`, `network_settings`, `destinations`, `last_used_destination_id`, `pc_pairings`). Config-object scale doesn't yet justify a database engine; migrate to `drift` (SQLite) later only if the data model grows past simple blobs.
- `flutter_secure_storage` **exclusively** for OAuth tokens and PC pairing shared secrets (iOS Keychain / Android Keystore-backed). Never store tokens in `shared_preferences`.
- New `lib/core/persistence/settings_repository.dart` (generic JSON-blob repository) and `secure_token_store.dart`.

### 1.3 Routing — go_router

The feature set implies at minimum: Settings home, Destinations list, per-platform OAuth/link screens, custom RTMP form, PC pairing (QR/PIN/manual — 3 sub-screens), Video/Audio/Network settings, and OAuth redirect deep links.

**Decision: `go_router`** — Flutter-team-maintained, declarative, first-class deep-link handling for the OAuth redirect step. New `lib/core/routing/app_router.dart`; replace `MaterialApp(home:)` with `MaterialApp.router(routerConfig: appRouter)` in `main.dart`.

### 1.4 Camera architecture — dual-output capture, deferred to Phase 5

`camera_preview_pane.dart` opens one `CameraController` purely for on-screen preview. Live streaming needs the same sensor to simultaneously feed the preview texture **and** a hardware encoder input, for up to two concurrent legs (RTMP-to-platform, WebRTC-to-PC) at potentially different resolutions/bitrates. The `camera` plugin does not expose a second encoder-ready output from one capture session, and opening a second independent session concurrently is unreliable across Android OEMs.

**Decision:** keep the `camera` plugin as-is through Phase 4 (nothing in settings/destinations/pairing needs it changed). Budget Phase 5 for a custom Camera2 (Android) / AVCaptureSession (iOS) capture layer that attaches both a preview `SurfaceTexture` and encoder `Surface`(s) to one session, exposed to Dart the same way screencast is (texture id + status via platform channel). This is flagged again in §3.6 as a top risk — prototype it as a standalone spike before scheduling Phase 5 for real.

### 1.5 Encoding & transport — two distinct legs

The two destination types have fundamentally different constraints; conflating them is the single biggest risk in this plan, so they're split:

**Leg A — PC client transport.** Both ends are owned by this product, so it does not need RTMP/RTMPS/SRT at all.

**Decision: `flutter_webrtc`** for the PC leg. One plugin provides hardware-accelerated capture+encode via `MediaStream` APIs, STUN/TURN/ICE for LAN and WAN NAT traversal, DTLS-SRTP encryption, built-in adaptive bitrate via congestion control (satisfies the "adaptive under poor network" requirement for this leg for free), and an `RTCDataChannel` usable for pairing/control/stats. "USB, shared network, and WAN" become one WebRTC peer connection whose *signaling* path differs (LAN: direct local exchange once discovered; WAN: via a small relay; USB: local port-forward carrying the same signaling+ICE) rather than three separate transports.

**Leg B — third-party platform streaming** (Twitch/YouTube/Facebook/Instagram/TikTok/Kick + custom RTMP/RTMPS/SRT). These require actually speaking RTMP/RTMPS/SRT to an ingest server, which WebRTC does not do. There is no maintained pure-Dart/Flutter-plugin RTMP/SRT publisher with hardware encoder control — this must be a native bridge, following the same platform-channel pattern as screencast.

**Decision:** evaluate **HaishinKit** (`HaishinKit.kt` for Android, `HaishinKit.swift` for iOS, same maintainer, BSD-3, actively maintained RTMP support on both) as the native publisher, wrapped by `com.streamphonecam/publisher` + `com.streamphonecam/publisher_events`, mirroring `ScreencastPlatform`/`ScreencastEvent` (status enum: idle/connecting/live/reconnecting/error + live stats: bitrate/dropped frames/RTT). Verify its current per-platform SRT coverage before committing; fall back to bridging `libsrt` directly if insufficient (real native/NDK work).

Two explicit warnings: **do not use `ffmpeg-kit`/`ffmpeg-kit-flutter`** — retired/archived upstream, no longer published. **AV1 encode is a capability-gated stretch goal**, not a baseline — hardware AV1 encoders exist only on a handful of recent flagship SoCs; query support at runtime (`MediaCodecList` / `VTCompressionSession`) and fall back to H.264/HEVC automatically.

### 1.6 Testing infrastructure

Add `mocktail` for mocking repositories/platform-channel wrappers, and an `integration_test/` directory for settings persistence round-trips, mode-toggle/record-button flow, and mocked-destination multistreaming. Add a unit test for `ScreencastPlatform` alongside its refactor (not currently tested) to set the pattern new platform wrappers (`PublisherPlatform`, `PcConnectionPlatform`, `LanDiscoveryPlatform`) should follow.

### 1.7 New dependencies

| Purpose | Package |
|---|---|
| State management | `flutter_riverpod` |
| Routing / deep links | `go_router` |
| Non-sensitive settings persistence | `shared_preferences` |
| Secure token/secret storage | `flutter_secure_storage` |
| PC transport (media + data channel + NAT traversal) | `flutter_webrtc` |
| OAuth browser flow | `flutter_web_auth_2` |
| LAN discovery (Dart-side mDNS) | `multicast_dns` (+ native NsdManager/NetService bridge) |
| QR generation / scanning | `qr_flutter` / `mobile_scanner` |
| Network state detection | `connectivity_plus` |
| Battery level | `battery_plus` |
| Keep screen awake | `wakelock_plus` |
| Local notifications | `flutter_local_notifications` |
| Native RTMP/SRT publisher | HaishinKit (Kotlin + Swift), bridged natively — not a Dart package |
| Test mocking | `mocktail` |

---

## 2. Phased milestones

### Phase 1 — Foundational architecture
**Builds:** Riverpod `ProviderScope` wiring; `go_router` skeleton (routes for the existing `CaptureScreen` plus a placeholder `SettingsScreen`); `lib/core/persistence/settings_repository.dart` + `secure_token_store.dart`; `lib/core/session/` (`StreamSessionState` + provider). Migrate `CaptureScreen`'s local `_mode`/`_screencastEvent` state into providers, preserving current behavior exactly.
**Touches:** `lib/main.dart`, `lib/features/capture/presentation/capture_screen.dart`, `pubspec.yaml`.
**New files:** `lib/core/routing/app_router.dart`, `lib/core/persistence/settings_repository.dart`, `lib/core/persistence/secure_token_store.dart`, `lib/core/session/stream_session_state.dart`, `lib/core/session/stream_session_provider.dart`.
**Depends on:** nothing — this is the base.
**Risks:** regressing the existing screencast reattachment race-cover during the `initState`/`dispose` → provider migration. Add a test locking in current behavior *before* refactoring.

### Phase 2 — Settings shell + persistence
**Builds:** Real `SettingsScreen` reachable from the gear icon (replacing `debugPrint('Open settings')` with navigation), a section-list layout (Destinations, PC Connection, Video, Audio, Network, On-screen, Battery & Performance, Notifications), and a generic typed settings-domain pattern (`XSettings` model + `XSettingsRepository` built on Phase 1's `SettingsRepository`) reused by every later settings screen.
**Touches:** `lib/features/capture/presentation/capture_screen.dart` (wire the gear icon).
**New files:** `lib/features/settings/presentation/settings_screen.dart`, `lib/features/settings/presentation/widgets/settings_section_tile.dart`, `lib/features/settings/domain/settings_section.dart`.
**Depends on:** Phase 1 (router, persistence).
**Risks:** low — scaffolding.

### Phase 3 — Destination / account management
**Builds:** `StreamDestination` domain model (platform enum incl. `custom`, credentials reference, per-destination resolution/bitrate override); `DestinationsRepository` (JSON persistence + secure token refs); per-platform OAuth link flow via `flutter_web_auth_2`; custom RTMP/RTMPS/SRT manual entry form (always available regardless of OAuth status — see §3.1); multistreaming toggle; default/last-used destination memory.
**New files:** `lib/features/destinations/domain/stream_destination.dart`, `lib/features/destinations/domain/platform_account.dart`, `lib/features/destinations/data/destinations_repository.dart`, `lib/features/destinations/data/oauth/twitch_oauth_client.dart` (one per platform), `lib/features/destinations/presentation/destinations_screen.dart`, `lib/features/destinations/presentation/widgets/platform_link_tile.dart`, `lib/features/destinations/presentation/widgets/custom_rtmp_form.dart`.
**Depends on:** Phase 1 (secure storage, session state), Phase 2 (settings shell to host this screen).
**Risks:** the biggest UX/product risk — see §3.1. Ship manual RTMP/RTMPS/SRT entry **first**, fully functional before any OAuth work, since it's the only destination type guaranteed to work for every platform.

### Phase 4 — PC pairing & transport
**Builds:** `flutter_webrtc` integration for the PC media/data leg; pairing UI (QR display+scan, PIN entry, manual IP/hostname fallback); LAN discovery via `multicast_dns` + a native NSD/Bonjour bridge (`com.streamphonecam/lan_discovery` + `_events`) for reliability; signaling exchange (LAN: direct; WAN: relay — new infra outside this repo, flag explicitly to the user); auto-reconnect (ICE restart/renegotiation on disconnect); "Send to PC only" mode (disables Leg B, gated by session provider); simultaneous PC + platform toggle (both legs share the Phase 5 camera session).
**New files:** `lib/features/pc_connection/domain/pairing_session.dart`, `lib/features/pc_connection/domain/pc_connection_status.dart`, `lib/features/pc_connection/data/pc_connection_platform.dart`, `lib/features/pc_connection/data/lan_discovery_platform.dart`, `lib/features/pc_connection/presentation/pairing_screen.dart`, `lib/features/pc_connection/presentation/qr_scan_page.dart`, `lib/features/pc_connection/presentation/pin_entry_page.dart`. Native: `android/.../LanDiscoveryPlugin.kt` (NsdManager), `ios/Runner/LanDiscoveryChannel.swift` (Bonjour), plus `NSLocalNetworkUsageDescription`/`NSBonjourServices` in `Info.plist` and `CHANGE_WIFI_MULTICAST_STATE` in `AndroidManifest.xml`.
**Depends on:** Phase 1 (session state), Phase 3 (screen conventions reused).
**Risks:** WAN traversal and iOS Local Network permission UX — see §3.3.

### Phase 5 — Encoding pipeline + video/audio settings
**Builds:** the native dual-output camera capture layer from §1.4; native RTMP/SRT publisher bridge (HaishinKit) behind `com.streamphonecam/publisher` + `_events`, following the `ScreenCaptureForegroundService` pattern on Android (new `PublisherForegroundService.kt`, `stopWithTask="false"`); Video Settings screen (resolution/fps/codec/bitrate, per-destination overrides feeding `StreamDestination.overrides`); Audio Settings screen (mic source, sample rate/bitrate, mono/stereo, headphone monitoring passthrough).
**Touches:** `lib/features/camera/presentation/camera_preview_pane.dart` (replace hardcoded `ResolutionPreset.high`/`enableAudio: true` with settings-provider-sourced values), `lib/features/capture/presentation/capture_screen.dart` (wire the record button's `debugPrint('Start stream')` stub to real publishing; make the status pill's placeholder stats real).
**New files:** `lib/features/streaming_engine/data/publisher_platform.dart`, `lib/features/streaming_engine/domain/publisher_event.dart`, `lib/features/video_settings/...`, `lib/features/audio_settings/...`. Native: `android/.../PublisherForegroundService.kt`, `android/.../CameraEncodeSession.kt`, `ios/Runner/CameraEncodeSession.swift`, `ios/Runner/PublisherChannel.swift`; extend `ios/BroadcastExtension/SampleHandler.swift` and `ScreenCaptureForegroundService.kt` to feed captured screencast frames into the same publisher pipeline.
**Depends on:** Phase 3 (destination/override models), Phase 4 (Leg A already exists as a WebRTC track).
**Risks:** the single riskiest phase — native camera rewrite + native encoder/muxer bridge on two platforms + iOS Broadcast Extension memory ceiling. See §3.2 and §3.6.

### Phase 6 — Network resilience + adaptive streaming
**Builds:** preferred-network setting (Wi-Fi only/cellular allowed/auto) via `connectivity_plus`; cellular data usage tracking + warnings (accumulate bytes-sent from publisher stats against a user-set cap); bandwidth test before going live; buffer size setting (encoder/muxer output queue depth, passed through `publisher_platform.dart`); connection retry/backoff behavior; adaptive bitrate/resolution — Leg A reuses WebRTC's built-in congestion control (just expose `RTCStatsReport` to the health overlay), Leg B needs a custom native quality controller reacting to socket backpressure and SRT loss/RTT stats, stepping bitrate down before falling back to resolution/fps step-down.
**Touches:** `lib/features/video_settings/...` (adaptive toggle), `lib/features/streaming_engine/data/publisher_platform.dart` (new stats fields).
**New files:** `lib/features/network_settings/domain/network_settings.dart`, `lib/features/network_settings/data/bandwidth_test.dart`, `lib/features/network_settings/presentation/network_settings_screen.dart`.
**Depends on:** Phase 4 (Leg A stats), Phase 5 (Leg B publisher stats).
**Risks:** avoiding visible quality "flapping" in adaptive step-down/step-up is a tuning problem — budget iteration time, not just build time.

### Phase 7 — On-screen overlays + battery/thermal + notifications
**Builds:** quick mute toggle (wired into the Phase 5 audio pipeline, disables the mic encoder input without stopping the stream); stream health stats overlay (bitrate/dropped frames/latency from `publisher_events`/WebRTC stats); battery saver mode (`battery_plus` monitoring → auto-lower quality preset); thermal throttling (Android `PowerManager` thermal listener API 29+, iOS `ProcessInfo.thermalState`, both via a new `com.streamphonecam/device_health` + `_events` pair); keep-screen-awake via `wakelock_plus`; background streaming (Android: extend the foreground-service pattern to the publisher service; iOS: scope as largely unsupported — see §3.5); connection-lost local notification via `flutter_local_notifications`, triggered off publisher/WebRTC status transitions to disconnected/error.
**Touches:** `lib/features/capture/presentation/capture_screen.dart` (mute toggle + overlay placement), `lib/features/camera/presentation/camera_preview_pane.dart` (overlay integration point).
**New files:** `lib/features/overlays/presentation/stream_stats_overlay.dart`, `lib/features/overlays/presentation/mute_toggle_button.dart`, `lib/features/battery_performance/domain/battery_performance_settings.dart`, `lib/features/battery_performance/data/device_health_platform.dart`, `lib/features/notifications/data/connection_alert_service.dart`. Native: `android/.../DeviceHealthPlugin.kt`, `ios/Runner/DeviceHealthChannel.swift`.
**Depends on:** Phase 5/6 (needs real stats and encoder controls to act on).
**Risks:** iOS background camera capture — see §3.5.

---

## 3. Hardest / riskiest parts

### 3.1 OAuth across six platforms
Not uniform feasibility:
- **Reliable now:** Twitch and YouTube both support OAuth 2.0 + PKCE for native/public clients (usable directly from the phone via `flutter_web_auth_2`, no backend secret needed). YouTube's Live Streaming API can programmatically return an RTMP ingest URL + stream key after linking.
- **Verify before committing schedule:** whether a platform's API actually exposes the RTMP stream key to third-party OAuth apps varies and changes over time — "OAuth linked" does not automatically mean "we can auto-fetch the key."
- **High risk / may not be available to an indie developer:** Instagram Live and TikTok Live third-party RTMP-producer access appear to be restricted/partner-gated. Facebook Live via the Graph API requires Meta app review for video-publishing permissions (multi-week lead time, rejection risk). Kick has no well-established public OAuth+live-management API.
- **Design consequence:** the manual RTMP/RTMPS/SRT entry form (Phase 3, built first) must be the universal always-available path for every platform. Never assume OAuth implies auto-provisioned stream keys — keep manual key entry visible even for "linked" accounts. Any platform whose OAuth requires a confidential client secret (no PKCE-only path) needs a minimal backend token-exchange proxy — new infrastructure outside this repo.

### 3.2 Native RTMP/SRT/AV1 encoding on both platforms
Use HaishinKit as the starting point rather than a from-scratch `MediaCodec`+RTMP-muxer implementation; verify current per-platform SRT coverage before relying on it, falling back to bridging `libsrt` directly if needed (real native/NDK work). Do not plan around `ffmpeg-kit` — retired/unmaintained. AV1 encode is capability-gated, not baseline.

**iOS screencast-mode streaming is uniquely constrained:** the Broadcast Upload Extension runs as a separate process with an ~50MB memory ceiling. Running a full RTMP publisher + hardware encoder inside it is tight. The realistic pattern: hardware-encode inside the extension (VideoToolbox is comparatively memory-light), forward already-encoded bytes to the main app process via the same App Group/IPC mechanism `ScreencastChannel.swift` already uses for status (extended to carry media data), and do the actual network publishing in the main process. This is a meaningfully different data path than Android's screencast path (where `ScreenCaptureForegroundService` can run the full publisher itself, same process).

### 3.3 LAN auto-discovery + WAN traversal for PC pairing
LAN: `multicast_dns` is a reasonable start but multicast delivery is unreliable on some Android OEM Wi-Fi power-saving states — back it with native `NsdManager`/Bonjour via a platform-channel bridge. Android needs `CHANGE_WIFI_MULTICAST_STATE` + a multicast lock; iOS 14+ needs `NSLocalNetworkUsageDescription` + `NSBonjourServices` and shows a one-time permission prompt users may decline — manual IP/hostname fallback is mandatory, not optional.

WAN: `flutter_webrtc` gives ICE/STUN/TURN "for free," but symmetric-NAT scenarios still need a TURN relay server (e.g. self-hosted `coturn`) — new backend infrastructure outside this repo. Some signaling/rendezvous channel is also needed to exchange SDP/ICE candidates before the P2P connection exists — flag a small always-on relay/signaling service to the user explicitly as new backend work.

### 3.4 Adaptive bitrate under poor network conditions
Leg A (WebRTC) gets this largely for free via libwebrtc's congestion control — the work is exposing `RTCStatsReport` to the UI, not reimplementing control. Leg B (RTMP/SRT) needs a custom native quality controller monitoring encoder-to-socket backpressure and SRT loss/RTT stats, stepping bitrate down before falling back to resolution/fps. Expect real device/network tuning time, not just implementation time.

### 3.5 iOS background camera capture
Not symmetric across platforms. Android can extend the existing foreground-service pattern to keep camera capture/publishing alive with a persistent notification. iOS does not generally permit continued camera capture once backgrounded/locked outside a small set of Apple-sanctioned background modes that a general camera-streaming app is unlikely to qualify for. **Scope "background streaming" as Android-only**; iOS should explicitly pause/stop capture on backgrounding and surface that limitation to the user rather than attempting an approach likely to be rejected in App Store review or simply not work.

### 3.6 Camera architecture change for simultaneous preview + encode
Replacing the `camera` plugin's role with a custom Camera2/AVCaptureSession capture layer feeding a preview texture and one-or-two encoder surfaces from a single session is real native camera-API work on two platforms, and a prerequisite for Phase 5 rather than something deferrable indefinitely. Prototype it in isolation (a throwaway native camera-to-encoder-to-file spike on each platform) before Phase 5 is scheduled for real, to get a concrete effort estimate before it blocks the rest of the plan.

---

## Critical files

- `lib/features/capture/presentation/capture_screen.dart` — the shared shell every phase wires into (gear icon → settings, record button → publisher, status pill → real stats, mode toggle → session state).
- `lib/features/screencast/data/screencast_platform.dart` and `lib/features/screencast/domain/screencast_status.dart` — the canonical method+event channel / typed-status pattern every new native bridge should mirror.
- `android/app/src/main/kotlin/com/example/stream_phone_cam/MainActivity.kt` and `ScreenCaptureForegroundService.kt` — the Android service-binding/foreground-service pattern `PublisherForegroundService` (Phase 5) and background streaming (Phase 7) must replicate.
- `ios/Runner/ScreencastChannel.swift` and `ios/BroadcastExtension/SampleHandler.swift` — the App-Group/Darwin-notification cross-process relay pattern Phase 5's extension-side encode-and-forward work must extend.
- `lib/features/camera/presentation/camera_preview_pane.dart` — today's single-consumer `CameraController` usage that Phase 5's dual-output camera architecture replaces.
- `pubspec.yaml` — where every dependency in §1.7 gets added, phase by phase.
