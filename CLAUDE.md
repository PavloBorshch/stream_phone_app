# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Flutter mobile app (Android + iOS) that turns a phone into a streaming camera/screencast source — the mobile half of a larger two-part product (a separate desktop app receives the stream, applies filters, and can re-broadcast or expose it as a virtual webcam; not part of this repo). The UI lets the user pick a capture source (Camera or Screencast) via a slider above the record button. Capture is real on both platforms, but there is still no actual network transport anywhere in the app — the "start stream" action in Camera mode is a stub (`debugPrint('Start stream')`), and Screencast mode only reaches a local "capturing" state (frames are not sent anywhere yet).

## Commands

- Install dependencies: `flutter pub get`
- Run app (debug, connected device/emulator): `flutter run`
- Static analysis (uses `flutter_lints` via `analysis_options.yaml`): `flutter analyze`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/<file>_test.dart`
- Build Android debug/release APK: `flutter build apk --debug` / `flutter build apk`
- Build iOS release: `flutter build ios` (cannot be built/tested on Windows — see iOS note below)

## Architecture

- `lib/main.dart` — app entry point. `StreamingApp` sets up a single dark-themed `MaterialApp` with `CaptureScreen` as the home route. No router/navigation stack.
- `lib/core/app_theme.dart` — centralized `ThemeData` (dark theme only, red-accent color scheme).
- `lib/features/capture/` — the shared capture screen: `presentation/capture_screen.dart` owns `CaptureMode` (camera/screencast) state, screen chrome (top/bottom bars, status pill, mode toggle, record button), and portrait orientation lock. It swaps its body between `CameraPreviewPane` and `ScreencastPreviewPane` by widget type (not `IndexedStack`), so Flutter's own `dispose()` lifecycle tears down the outgoing pane's controller/capture session for free.
- `lib/features/camera/presentation/camera_preview_pane.dart` — owns the `camera` package's `CameraController` lifecycle (init, dispose, switch-camera).
- `lib/features/screencast/` — screencast capture: `data/screencast_platform.dart` wraps the native platform channels (`MethodChannel('com.streamphonecam/screencast')`, `EventChannel('com.streamphonecam/screencast_events')`); `domain/screencast_status.dart` defines `ScreencastStatus`/`ScreencastEvent`; `presentation/screencast_preview_pane.dart` renders a live `Texture` preview on Android (once capturing) or a status card on iOS (live in-app preview isn't possible there — see below); `presentation/widgets/broadcast_picker_button.dart` wraps iOS's `RPSystemBroadcastPickerView` as a `UiKitView`.
- Feature code lives under `lib/features/<feature>/presentation/...` (plus `domain/`, `data/` where relevant) — follow this feature-first structure when adding new features.

### Screencast capture — platform asymmetry (important)

Android's `MediaProjection` runs in-process. Capture is deliberately **not** tied to the Flutter widget/Activity lifecycle: `ScreenCaptureForegroundService.kt` (`android/app/src/main/kotlin/com/example/stream_phone_cam/`) owns the `MediaProjection`/`VirtualDisplay` itself and only stops on an explicit user action (or the system's own "Stop casting" control) — never because the UI pane unmounted. `MainActivity.kt` binds to this service (`bindService`, same-process `LocalBinder`) rather than owning capture objects directly, so switching to Camera mode or closing/reopening the app doesn't interrupt an in-progress screencast: `configureFlutterEngine` re-binds on every new Activity/engine, and if the service is already capturing, it re-points the running `VirtualDisplay` at a freshly registered `Texture` via `VirtualDisplay.setSurface()` (a texture entry is only valid for the `TextureRegistry`/engine that created it, so it must be recreated whenever a new engine attaches). `ScreencastPlatform.getStatus()` (called from `CaptureScreen.initState()`) plus a status push on both `EventChannel.onListen` and service (re)connection cover the race between the service reattaching and Dart subscribing, so either ordering still delivers the current state. The service is declared `android:stopWithTask="false"` so swiping the app from Recents doesn't tear it down either — though note Android has a hard limit here: if the OS fully kills the process (e.g. force-stop, memory reclaim), the `MediaProjection` consent is gone for good and capture cannot resume without the user re-approving the system dialog.

iOS forbids in-process system-wide screen capture. It requires a separate **Broadcast Upload Extension** target (its own process) that can only be *started* by the user tapping `RPSystemBroadcastPickerView` (Apple disallows programmatic start). Status is relayed back to the main app via an **App Group** shared container + Darwin notification, not a direct call. Source for this exists at `ios/Runner/ScreencastChannel.swift`, `ios/Runner/BroadcastPickerViewFactory.swift`, and `ios/BroadcastExtension/SampleHandler.swift`, but:
- The `BroadcastExtension` Xcode target itself does **not exist yet** — it must be created via Xcode's File → New → Target → Broadcast Upload Extension (this can't be done by hand-editing `project.pbxproj`), then its generated `SampleHandler.swift`/`Info.plist` replaced with the pre-authored files under `ios/BroadcastExtension/`.
- The App Group id and bundle identifiers used throughout (`group.com.example.stream_phone_cam.shared`, `com.example.stream_phone_cam.BroadcastExtension`) are **placeholders** — `com.example.*` cannot be registered as a real App Group. Update the `appGroupID`/bundle-id constants in `ScreencastChannel.swift`, `SampleHandler.swift`, and `BroadcastPickerViewFactory.swift` once the app has a real bundle id and a registered App Group.
- ReplayKit broadcast extensions cannot be tested in the iOS Simulator — a physical device and paid Apple Developer account (for the App Group) are required.
- This project's `AppDelegate.swift` uses Flutter's implicit-engine template (`didInitializeImplicitFlutterEngine`), not the classic `application(_:didFinishLaunchingWithOptions:)` plugin-registration pattern — keep that in mind when wiring any future native iOS integration.

## Platform config

- Camera/mic/screencast permissions: Android — `CAMERA`, `RECORD_AUDIO`, `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PROJECTION`, `POST_NOTIFICATIONS` in `android/app/src/main/AndroidManifest.xml`. iOS — `NSCameraUsageDescription`/`NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`; keep both platforms' declarations in sync when camera/mic/network/capture usage changes.
- iOS App Group entitlement: `ios/Runner/Runner.entitlements` (main app) and `ios/BroadcastExtension/BroadcastExtension.entitlements` (extension, once the target exists) — both currently use the `com.example.*` placeholder group id noted above.
- Flutter SDK constraint: `^3.12.2` (see `pubspec.yaml`).

## Dependencies

- `camera` — camera preview/control.
- `flutter_lints` — lint rules used by `flutter analyze`.
- Screencast uses raw platform channels, not a pub package — no maintained plugin combines an app-owned ReplayKit extension + App Group with a Texture-backed Android preview.

## Mistakes log

Whenever Claude Code makes a mistake while working in this repo (wrong assumption, broken command, incorrect edit, etc.), document it in `MISTAKES.md` — what happened, why, and how it was fixed — so future sessions don't repeat it.

## Rules

You must follow the rules in `RULES.md` for every request.
