# Local patch notes — HaishinKit.kt 0.18.2

This is a vendored copy of two Gradle modules from
[shogo4405/HaishinKit.kt](https://github.com/shogo4405/HaishinKit.kt), pinned
to **tag `0.18.2`, commit `7b745bcaadc9afc40413150d74d0934b00f41390`**:

- `haishinkit/` — capture/encode/compositing (`com.haishinkit.gles`,
  `com.haishinkit.gles.screen`, `com.haishinkit.media`, `com.haishinkit.screen`,
  etc.)
- `rtmp/` — the RTMP/RTMPS publisher (`com.haishinkit.rtmp`), depends on
  `haishinkit` via `api(project(":haishinkit"))`.

It exists for one reason: a real device this app was tested on (see "The bug
this patch fixes" below) never produced usable video from either its own
camera preview or any publishing leg, and the root cause lives inside
`com.haishinkit.gles.screen.Screen` — code this repo cannot patch while it's
a binary dependency resolved from JitPack. Same rationale
`third_party/flutter_webrtc` already documents for itself in its own
`PATCH_NOTES.md` — read that file first if you haven't; this one follows the
same conventions.

## What was vendored, and what was trimmed

Upstream's repo root also has `app/`, `compose/`, and `lottie/` modules (a
demo app, a Jetpack Compose helper, and a Lottie overlay helper) — none of
this app depends on any of them (verified: `grep -rn
"com.haishinkit.lottie\|com.haishinkit.compose\|com.haishinkit.app\." to confirm
no cross-references exist from `haishinkit/`'s or `rtmp/`'s own `src/main`).
Only `haishinkit/src/main` and `rtmp/src/main` were copied in (no
`src/test`/`src/androidTest` — this app doesn't run HaishinKit's own test
suite, only its own `flutter test`/`gradlew :app:testDebugUnitTest`), plus
each module's `build.gradle.kts`, `consumer-rules.pro`, and
`proguard-rules.pro`, plus the repo's root `LICENSE.md` (BSD 3-Clause).

## How the Gradle wiring points here instead of JitPack

- `android/settings.gradle.kts` — `include(":haishinkit")`/`include(":rtmp")`,
  each with `projectDir` pointed at
  `third_party/HaishinKit.kt/{haishinkit,rtmp}` (a relative path from
  `android/`), the same "local module, not a downloaded artifact" pattern
  `third_party/flutter_webrtc`'s `dependency_overrides: { path: ... }` uses
  for the Dart side — just expressed the Gradle way, since HaishinKit.kt is a
  plain Gradle/Maven dependency, not a Flutter/pub package.
- `android/app/build.gradle.kts` — `implementation(project(":haishinkit"))`
  / `implementation(project(":rtmp"))`, replacing
  `implementation("com.github.HaishinKit.HaishinKit~kt:{haishinkit,rtmp}:0.18.2")`.
- Each vendored module's own `build.gradle.kts` is adapted from upstream's:
  the `maven-publish`/`dokka` plugins and upstream's version-catalog
  (`libs.xxx`) aliases are dropped (this app has no
  `gradle/libs.versions.toml` wired in), and dependency versions are instead
  copied **verbatim** from upstream's own `gradle/libs.versions.toml` at this
  tag (`androidx.core:core-ktx:1.17.0`,
  `org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2`,
  `org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0`,
  `androidx.appcompat:appcompat:1.7.1`, `com.google.android.material:material:1.12.0`).
  `namespace`, `compileSdk`/`minSdk`, `compileOptions`, and the dependency
  *list itself* are otherwise unchanged from upstream.
- The JitPack Maven repository entry in `android/build.gradle.kts` was left
  in place (harmless if unused) rather than removed, in case anything else
  ever needs it; nothing in this app currently does.

**Verified as an unmodified baseline first**, per the plan for this change:
before any patch was applied, `flutter build apk --debug` was run against
this vendored-but-unpatched copy and produced a build that behaved
identically to the JitPack-fetched 0.18.2 on the real device (same IMGSRV
errors, same black preview — see below) — confirming the vendoring itself
introduced no behavior change, so the patch's effect is measurable against a
known-identical starting point.

## The bug this patch fixes

**Symptom:** on a real device (OPPO CPH2179 — MediaTek MT6765 SoC, PowerVR
Rogue GE8320 GPU, Android 10 / API 29), the phone's own camera preview
(`FlutterTexturePreview`) rendered solid black — `CAMERA | READY` shown, no
image — **even with no publishing/WebRTC/PC-pairing code involved at all**,
just the default capture screen. `adb logcat` showed, continuously, once per
produced frame:

```
E/IMGSRV: :0: IsTextureConsistent: IMGEGLImage is not consistent
E/IMGSRV: :0: ScheduleTA: Skipping render from different gc/thread!
E/IMGSRV: :0: KEGLSetMTKUpdateTime: Not valid handle
I/BufferQueueProducer: [SurfaceTexture-0-...] queueBuffer: slot N is dropped, handle=...
```

This was originally suspected (in the bug report that led to this
investigation) to be an EGL/thread conflict between the Flutter preview path
and the newly-added WebRTC "Leg A" output (`WebRtcCameraOutput.kt`). Direct
measurement disproved that: the errors and the black preview reproduce with
only `CameraEncodeSession`/`FlutterTexturePreview` active, before Leg A ever
constructs anything.

**Root cause, traced into this exact HaishinKit.kt source (not guessed):**
`com.haishinkit.media.MediaMixer.screen` is a
`com.haishinkit.gles.screen.ThreadScreen`, which runs an inner
`com.haishinkit.gles.screen.Screen` on its own dedicated `HandlerThread`.
That inner `Screen` composites every video frame into an FBO
(`Framebuffer`, `haishinkit/src/main/java/com/haishinkit/gles/Framebuffer.kt`)
— never presented to any window, only sampled by other threads
(`FlutterTexturePreview`'s/each RTMP `Stream`'s/`WebRtcCameraOutput`'s own
`PixelTransform`, each on its own thread, sharing this `Screen`'s texture
namespace). Its `startRunning()` (originally):

```kotlin
override fun startRunning() {
    if (isRunning.get()) return
    isRunning.set(true)
    graphicsContext.open(null)
    graphicsContext.makeCurrent(null)   // <-- eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context)
    choreographer = Choreographer.getInstance()
}
```

establishes this thread's EGL context with **no real surface at all**
("surfaceless", relying on `EGL_KHR_surfaceless_context`/
`GL_OES_surfaceless_context`). `Framebuffer.render { ... }` always ends by
rebinding to the default framebuffer (`glBindFramebuffer(GL_FRAMEBUFFER,
0)`) — with no real window/pbuffer surface ever bound to this context,
"framebuffer 0" has no well-defined backing. Every one of the three IMGSRV
error strings above is consistent with the PowerVR driver's internal state
being left inconsistent by this: `IsTextureConsistent`/`KEGLSetMTKUpdateTime`
report invalid/inconsistent EGLImage and timestamp handles, and `ScheduleTA`
(the Tile Accelerator scheduler, PowerVR's tile-based-deferred-rendering
work queue) refuses to schedule rendering it considers to be coming from a
mismatched graphics-context/thread pairing.

Confirmed this isn't an unusual calling pattern on this app's part: upstream's
own official example (`app/src/main/java/com/haishinkit/app/CameraViewModel.kt`,
same 0.18.2 tag) touches `mixer.screen`/registers outputs the same way this
app does — so the trigger is the device/driver, not a misuse of the API.

## The patch

**`haishinkit/src/main/java/com/haishinkit/gles/GraphicsContext.kt`** — added
`createPbufferSurface(width: Int, height: Int): EGLSurface?`, a thin wrapper
around `EGL14.eglCreatePbufferSurface` (mirrors the existing
`createWindowSurface` method's shape exactly).

**`haishinkit/src/main/java/com/haishinkit/gles/screen/Screen.kt`** —
`startRunning()` now does:

```kotlin
graphicsContext.makeCurrent(graphicsContext.createPbufferSurface(PBUFFER_WIDTH, PBUFFER_HEIGHT))
```

instead of `graphicsContext.makeCurrent(null)` — a real, if literally 1x1,
pbuffer surface, so this thread's context always has a genuine EGL surface
backing its default framebuffer, on every driver, surfaceless-capable or
not. `PBUFFER_WIDTH`/`PBUFFER_HEIGHT` (both `1`) are new `private const val`s
on `Screen`'s companion object — the surface is never actually presented
(only ever used as the target of `glBindFramebuffer(GL_FRAMEBUFFER, 0)`
inside `Framebuffer.render`'s FBO unbind), so its size is irrelevant beyond
"large enough for EGL to accept."

This is the smallest change that addresses the traced mechanism: two lines
of behavior change (`makeCurrent`'s argument) plus one small new helper
method, no change to `PixelTransform.kt`/`ThreadPixelTransform.kt`/any other
consumer, and no change to `Screen.kt`'s `stopRunning()` (the existing
`GraphicsContext.close()`/`release()` path already destroys whatever real
`EGLSurface` is stored in `this.surface`, which now correctly includes this
pbuffer instead of always being `EGL_NO_SURFACE`).

## What this patch measurably did and did not fix

Verified on the same real device (OPPO CPH2179), via a controlled A/B test —
not just "it looks better now": with the patch reverted to
`makeCurrent(null)` (a one-line temporary change, then restored), the
preview reproducibly went black again under otherwise-identical physical
conditions (same room, same phone position, back-to-back runs); with the
patch applied, it reproducibly showed live video. This rules out a
lighting/physical-environment confound — the patch is what changed the
outcome, twice, in both directions.

- **Fixed:** the camera preview, which was solid black before this patch on
  this device, now renders real video. Confirmed across three independent
  fresh installs.
- **Fully eliminated:** the `IsTextureConsistent: IMGEGLImage is not
  consistent` and `KEGLSetMTKUpdateTime: Not valid handle` log lines — zero
  occurrences in multiple 15-second captures after the patch, versus
  continuous (dozens per capture) before it.
- **Not eliminated, but no longer preventing correct output:**
  `ScheduleTA: Skipping render from different gc/thread!` and occasional
  `BufferQueueProducer ... queueBuffer: slot N is dropped` still appear in
  logcat, fairly frequently (tens per 15-second window) — but the preview is
  visibly correct despite them, consistent with the driver silently dropping
  and recovering individual stale/duplicate frames rather than corrupting
  the output. A `GLES20.glFinish()` in place of `Screen.doFrame()`'s
  trailing `GLES20.glFlush()` was tried as an additional, more invasive fix
  attempt for this remaining signature — it made no measurable difference
  (same error rate, same visual result) and was **reverted**, since it adds
  per-frame blocking overhead for no benefit and this patch is meant to stay
  small.
- **Not investigated further:** a full elimination of the remaining
  `ScheduleTA` messages would likely require avoiding HaishinKit's
  multi-threaded rendering architecture altogether (one dedicated GL thread
  per `Screen`, and a *separate* dedicated GL thread per output/
  `PixelTransform`, all sharing one texture namespace) — e.g. rendering
  everything on a single shared thread instead. That is a real architectural
  change, not a small patch, and was deliberately not attempted here.

## Producer/consumer fence sync (second patch, added later)

**What this is not:** a fix for the `ScheduleTA: Skipping render from
different gc/thread!` log line above. That line is still expected. See "Why
we know a fence doesn't silence `ScheduleTA`" below before assuming otherwise.

**What this is:** `com.haishinkit.gles.screen.Screen`'s compositor thread
writes every frame's composited image into one shared FBO texture
(`textureId`); every consumer — `FlutterTexturePreview`'s preview, each RTMP
leg's `Stream`, and Leg A's `WebRtcCameraOutput` — reads that same texture
from its own independently-clocked `PixelTransform`, on its own thread, in
its own share-grouped GL context (confirmed by grep: `screen.textureId` has
exactly one consumer call site in this codebase,
`gles/PixelTransform.kt`'s `doFrame()`, so this covers every consumer).
Before this patch, there was **no GL-level synchronization primitive
anywhere** between that write and any of those reads — producer and
consumers each ran their own `Choreographer` loop with no handshake, so a
consumer's sample of `textureId` was not ordered against the compositor's
most recent write to it by anything but timing coincidence. Undefined
per the GLES spec, independent of whether it visibly tears in practice.

The fix adds a GL fence sync object as a happens-before edge between the
write and each read:

- `com.haishinkit.screen.Screen.textureFenceSync` (`Long`, default `0L`) —
  new abstract-class property, doc-commented in place, mirroring
  `textureId`'s own "not yet bound" `-1`/`0` sentinel pattern.
- `com.haishinkit.gles.screen.Screen` overrides it as `@Volatile`. At the end
  of `doFrame()`, after the FBO write (`framebuffer.render { ... }`) and
  before the trailing `glFlush()`, it publishes a new fence — created via
  `GLES30.glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)` — and only *then*
  deletes the previous frame's fence (`GLES30.glDeleteSync`). That order is
  load-bearing: per the GLES spec a sync object's *name* stops being valid
  the instant `glDeleteSync` is called on it (the underlying object itself
  is kept alive until signaled, but the client-visible name is not), so
  deleting the old fence before publishing the new one would leave a window
  where the shared field held an already-invalid handle for any consumer
  thread that happened to read it right then. Publishing first means the
  field only ever transitions between two valid handles. `stopRunning()`
  deletes whatever fence is still outstanding at teardown; this is safe
  because `doFrame()`/`startRunning()`/`stopRunning()` are all only ever
  invoked serialized on the compositor's own `HandlerThread` (via
  `ThreadScreen`'s `Handler`), so there is no concurrent producer-side access
  to race against, only the producer-vs-consumer race the fence itself
  addresses. Both the fence-create and fence-delete calls are guarded by
  `graphicsContext.version >= 3` — `glFenceSync`/`glDeleteSync`/`glWaitSync`
  are GLES3 core with no ES2 extension equivalent, and `GraphicsContext.open()`
  can fall back to an ES2 context on a device that can't negotiate ES3.
- `com.haishinkit.gles.screen.ThreadScreen` forwards the property read-only
  (`get() = screen.textureFenceSync`), the same pass-through pattern it
  already uses for `textureId`.
- `com.haishinkit.gles.PixelTransform.doFrame()` reads `screen.textureFenceSync`
  once per frame and, if non-zero, calls `GLES30.glWaitSync(fence, 0,
  GL_TIMEOUT_IGNORED)` before its draw call. This is deliberately
  `glWaitSync`, **not** `glClientWaitSync`: `glWaitSync` is a GPU-side wait
  inserted into the consumer's own command stream (order the *upcoming draw*
  after the fence), and never blocks the calling (consumer) thread; a
  CPU-blocking `glClientWaitSync` here would cost real latency on every
  registered output, every frame, for a device class (PowerVR/MediaTek) that
  is already tight on this exact rendering path — not worth it for insurance
  against a race with no observed visual symptom. Sync objects are shared
  within a share group per the GLES spec, so waiting in a consumer's context
  on a fence created in the producer's (share-grouped) context is valid
  usage. Guarded by the same `graphicsContext.version >= 3` check, on the
  consumer's own context this time (a consumer can independently fall back
  to ES2 even if the compositor didn't).
- A `0L` fence value (nothing composited yet, or an ES2 fallback context that
  never creates one) is a no-op on both sides — the producer never publishes
  one, the consumer's `takeIf { it != 0L }` skips the wait.

**Why we know a fence doesn't silence `ScheduleTA`:** the "What this patch
measurably did and did not fix" section above already recorded a
`GLES20.glFinish()` experiment — a strictly *stronger* guarantee than any
fence, since it blocks the producer thread until the GPU has actually
finished, not merely orders a later GPU command after a marker — and it
produced **zero measurable change** in the `ScheduleTA` rate. That result is
why this fence is documented, from the start, as insurance against a
race that is undefined-but-not-observed-to-tear, not as an attempt to
quiet that log line: if `glFinish()` (strictly stronger) didn't touch it,
a `glFenceSync`/`glWaitSync` pair (weaker) has no realistic chance of doing
so either. The driver's `ScheduleTA` complaint tracks GL context/thread
*identity* at the point it schedules tile-accelerator work, not data
readiness — a problem a fence has no mechanism to address.

**Why full elimination was declined:** the only way to actually remove the
`ScheduleTA` message (as opposed to insuring against the race alongside it)
is to stop rendering from multiple threads/contexts against the shared
texture at all — i.e., serialize every consumer (preview, every RTMP leg,
Leg A) onto the compositor's own thread instead of each running its own
`PixelTransform`. That is a genuine architectural change to
`com.haishinkit.gles`'s threading model, not a small patch, carries real risk
to every existing consumer, and was **explicitly declined by the user** in
favor of this fence plus a logcat filter for the console noise (see
`CLAUDE.md`'s Android debugging notes) — do not re-derive "just serialize
everything" as a fix for this log line without revisiting that decision with
the user first.

## If a future HaishinKit.kt release fixes this upstream

As of this writing, 0.18.2 is still the latest published release (checked
via `gh api repos/shogo4405/HaishinKit.kt/releases`). If a later release
changes `Screen.startRunning()`'s EGL setup, re-check whether this patch is
still needed before re-applying it during an upgrade — re-run the same A/B
test on a PowerVR/MediaTek device before assuming either way.

## Upgrading this vendored copy

Same process as `third_party/flutter_webrtc/PATCH_NOTES.md` describes for
itself: copy the new tag's `haishinkit/src/main` and `rtmp/src/main` (and the
two `consumer-rules.pro`/`proguard-rules.pro` pairs) over this directory,
then re-apply the two edits above (diff against a fresh checkout of the new
tag if useful) and re-check `build.gradle.kts`'s hardcoded dependency
versions against the new tag's `gradle/libs.versions.toml`. Re-run
`flutter analyze` and `flutter build apk --debug` afterward, and re-test on
a real PowerVR/MediaTek device per the "what this patch did and did not fix"
section above before dropping the patch.
