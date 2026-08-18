# Mistakes Log

A running log of mistakes made by Claude Code while working in this repo — what happened, why, and how it was fixed. Kept so future sessions can avoid repeating them.

## Format

```
## YYYY-MM-DD

- **What happened:** ...
- **Root cause:** ...
- **Fix:** ...
- **The rule that prevents a repeat:** ...
```

## 2026-08-17

- **What happened:** Built `LanguageSettingsScreen`'s picker using `RadioListTile(groupValue: ..., onChanged: ...)` directly, which produced deprecation warnings under `flutter analyze`.
- **Root cause:** On this project's Flutter version (3.44.9 / SDK ^3.12.2), `Radio`/`RadioListTile`'s `groupValue`/`onChanged` params were deprecated after 3.32.0 in favor of a `RadioGroup<T>` ancestor widget that owns the selection state; this is a recent API change not reflected in older tutorials/examples.
- **Fix:** Wrapped the list in `RadioGroup<AppLocale>(groupValue: ..., onChanged: ..., child: ListView(...))` and dropped `groupValue`/`onChanged` from the individual `RadioListTile`s.
- **The rule that prevents a repeat:** When adding any `Radio`/`RadioListTile`/`RadioMenuButton` usage, check `flutter analyze` output for deprecation warnings before considering the widget done — this Flutter version expects the `RadioGroup` ancestor pattern, not per-widget `groupValue`/`onChanged`.

- **What happened:** A widget test (`settings_navigation_test.dart`) pumped `SettingsScreen`'s `ListView.separated` at the default test surface size and asserted `find.text(...)` for all 9 section tiles; the last section ("Notifications & Alerts") wasn't found even though it was correctly rendered in the widget tree logic.
- **Root cause:** `ListView.separated` lazily builds only the children that fit the viewport. The default `flutter_test` surface is too short to fit 9 `ListTile`s + dividers, so off-screen items are never built/found by `find.text`.
- **Fix:** Called `tester.binding.setSurfaceSize(const Size(800, 2000))` before pumping (with `addTearDown` to reset it), so every list item is realized.
- **The rule that prevents a repeat:** When a widget test asserts on multiple items inside a scrollable list (`ListView`, `CustomScrollView`, etc.), either enlarge the test surface size or scroll to each item — don't assume `find.text` sees off-screen lazy-built children.

- **What happened:** `flutter build apk --debug` failed with `Could not determine the dependencies of task ':flutter_secure_storage:compileDebugJavaWithJavac' ... Failed to find target with hash string 'android-37' in ... sdk`, after adding `flutter_secure_storage: ^11.0.0` via `flutter pub add`.
- **Root cause:** `flutter_secure_storage` 11.0.0 hardcodes `compileSdk = 37` in its own `android/build.gradle` (independent of the app module's `compileSdk = flutter.compileSdkVersion`). The locally installed Android SDK only has the platform registered under the folder/hash `android-37.0` (a fractional-versioned Android 17 "Baklava" release), not the plain `android-37` hash AGP looks up — a real mismatch between this bleeding-edge plugin release and the currently available SDK platform packaging, not something fixable by just running the Android SDK Manager for "platform 37".
- **Fix:** Pinned `flutter_secure_storage: ^10.0.0` (`flutter pub add flutter_secure_storage:^10.0.0`), whose `android/build.gradle` uses `compileSdk 36` — already installed locally (`android-36`). `flutter build apk --debug` then succeeded.
- **The rule that prevents a repeat:** Don't blindly accept whatever version `flutter pub add`/`pub get` resolves to for Android-native plugins. If a Gradle build fails with `Failed to find target with hash string 'android-N'`, check that plugin's own `android/build.gradle`(`.kts`) for a hardcoded `compileSdk` before assuming an SDK Manager install will fix it — the newest plugin release may require a not-yet-properly-packaged Android API level; pinning to the next older plugin release that targets an already-installed platform is usually faster and safer than chasing SDK platform installs for a brand-new API level.
