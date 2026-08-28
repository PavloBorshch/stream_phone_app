package com.example.stream_phone_cam

import android.content.Context
import android.graphics.Rect
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.projection.MediaProjection
import android.util.Log
import com.haishinkit.media.AudioMixerSettings
import com.haishinkit.media.MediaMixer
import com.haishinkit.media.MediaOutput
import com.haishinkit.media.source.AudioRecordSource
import com.haishinkit.media.source.Camera2Source
import com.haishinkit.media.source.MediaProjectionSource
import io.flutter.view.TextureRegistry

/**
 * The single capture session PLAN.md §1.4 specifies: one open camera (or one
 * MediaProjection) feeding a preview surface *and* the hardware encoder(s) at
 * the same time, rather than the `camera` plugin's preview-only session that
 * cannot also hand frames to an encoder.
 *
 * HaishinKit's [MediaMixer] is the capture/compositing layer: video and audio
 * sources are attached to it, and every consumer — each publishing
 * [com.haishinkit.stream.Stream] plus [FlutterTexturePreview] — is registered
 * as a [MediaOutput] on it. Adding a second destination is therefore
 * registering a second output on the same mixer, not opening the camera
 * twice, which is what makes multistreaming possible at all.
 *
 * Deliberately owned by [PublisherForegroundService] rather than the Flutter
 * engine: capture has to survive the Activity being destroyed and recreated,
 * exactly as `ScreenCaptureForegroundService` does for screencast.
 */
class CameraEncodeSession(
    private val context: Context,
) {
    val mixer: MediaMixer by lazy { MediaMixer(context) }

    var isRunning: Boolean = false
        private set

    /** Which physical camera is open, so the UI can label the switch button. */
    var lensFacingFront: Boolean = false
        private set

    var previewWidth: Int = 0
        private set

    var previewHeight: Int = 0
        private set

    private var preview: FlutterTexturePreview? = null
    private var cameraSource: Camera2Source? = null
    private var audioSource: AudioRecordSource? = null
    private var projectionSource: MediaProjectionSource? = null

    val previewTextureId: Long? get() = preview?.textureId

    /**
     * Opens the camera and starts the mixer. Safe to call while already
     * running with the same lens (no-op) — reopening is only done for a
     * genuine camera switch, since it drops frames.
     */
    suspend fun startCamera(front: Boolean, width: Int, height: Int) {
        if (isRunning && cameraSource != null && lensFacingFront == front) return

        // width/height arrive as the configured VideoSettings resolution,
        // always given landscape-style (e.g. 1920x1080) — but this app is
        // portrait-locked (CLAUDE.md), and HaishinKit picks the camera's
        // sensor stream size (Camera2Output.getCameraSize) *from
        // mixer.screen.frame*'s aspect ratio, with no orientation
        // compensation of its own (confirmed against HaishinKit.kt's own
        // example app, CameraViewModel.onConfigurationChanged, which sets
        // this same Rect on rotation). Left at the mixer's landscape
        // default (1280x720), the camera opens a landscape sensor stream
        // that every consumer — this preview, every RTMP leg, Leg A's
        // WebRTC output — then crops/scales into a portrait box, which is
        // what "zoomed in" actually was: not too much crop, but cropping a
        // landscape frame to a portrait shape while showing it uncropped
        // in every OTHER direction.
        val (pw, ph) = portraitSize(width, height)
        previewWidth = pw
        previewHeight = ph
        mixer.screen.frame = Rect(0, 0, pw, ph)
        lensFacingFront = front

        val cameraId = resolveCameraId(front) ?: run {
            Log.w(TAG, "no camera matching front=$front")
            return
        }

        projectionSource = null
        val source = Camera2Source(context, cameraId)
        cameraSource = source
        mixer.attachVideo(VIDEO_TRACK, source).onFailure {
            Log.e(TAG, "attachVideo failed", it)
        }
        start()
    }

    /**
     * Feeds the mixer from an existing [MediaProjection] instead of the
     * camera. The projection itself stays owned by
     * `ScreenCaptureForegroundService` — this only adds a second consumer of
     * it, so stopping publishing never tears down a capture the user started
     * separately.
     */
    suspend fun startScreencast(projection: MediaProjection) {
        cameraSource = null
        val source = MediaProjectionSource(context, projection)
        projectionSource = source
        mixer.attachVideo(VIDEO_TRACK, source).onFailure {
            Log.e(TAG, "attachVideo(projection) failed", it)
        }
        start()
    }

    /**
     * Attaches the microphone. Kept separate from [startCamera] so the app
     * only holds the mic while it is actually publishing — a preview that
     * silently occupied the microphone would block other apps and light up
     * the system recording indicator for no reason.
     */
    suspend fun startMicrophone(sampleRate: Int) {
        if (audioSource != null) return
        val source = AudioRecordSource(context).apply {
            this.sampleRate = sampleRate
        }
        audioSource = source
        mixer.attachAudio(AUDIO_TRACK, source).onFailure {
            Log.e(TAG, "attachAudio failed", it)
        }
    }

    suspend fun stopMicrophone() {
        if (audioSource == null) return
        audioSource = null
        mixer.attachAudio(AUDIO_TRACK, null)
    }

    fun setMuted(muted: Boolean) {
        mixer.audioMixerSettings = AudioMixerSettings(isMuted = muted)
    }

    private fun start() {
        if (!isRunning) {
            mixer.startRunning()
            isRunning = true
        }
    }

    /**
     * (Re)binds the preview to [registry]. Called on every new Flutter engine
     * — a texture entry belongs to the engine that created it, so the old one
     * is released and a fresh one registered rather than reused.
     */
    fun attachPreview(registry: TextureRegistry, width: Int, height: Int): Long {
        // Callers pass either the raw requested resolution (first attach)
        // or the already-portrait previewWidth/previewHeight this class
        // stored (re-attach on a new engine, see startCamera's note) —
        // portraitSize() is idempotent on an already-portrait pair, so
        // applying it unconditionally is safe either way.
        val (pw, ph) = portraitSize(width, height)
        detachPreview()
        val entry = registry.createSurfaceTexture()
        val created = FlutterTexturePreview(context, entry, pw, ph)
        preview = created
        mixer.registerOutput(created)
        previewWidth = pw
        previewHeight = ph
        return created.textureId
    }

    fun detachPreview() {
        preview?.let {
            mixer.unregisterOutput(it)
            it.release()
        }
        preview = null
    }

    fun registerOutput(output: MediaOutput) = mixer.registerOutput(output)

    fun unregisterOutput(output: MediaOutput) = mixer.unregisterOutput(output)

    /**
     * Tears the capture session down completely. Note this does *not* stop a
     * MediaProjection obtained from `ScreenCaptureForegroundService` — that
     * one belongs to the screencast feature's own lifecycle.
     */
    suspend fun release() {
        detachPreview()
        mixer.attachVideo(VIDEO_TRACK, null)
        mixer.attachAudio(AUDIO_TRACK, null)
        cameraSource = null
        audioSource = null
        projectionSource = null
        if (isRunning) {
            mixer.stopRunning()
            isRunning = false
        }
        mixer.dispose()
    }

    /**
     * Swaps a landscape-style (width > height) resolution to portrait —
     * this app is always portrait-locked, so the smaller dimension is
     * always the width. Idempotent: applying it to an already-portrait pair
     * is a no-op, which is what lets every caller apply it unconditionally
     * regardless of whether its input has been swapped already.
     */
    private fun portraitSize(width: Int, height: Int): Pair<Int, Int> =
        minOf(width, height) to maxOf(width, height)

    private fun resolveCameraId(front: Boolean): String? {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val wanted =
            if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
        return try {
            manager.cameraIdList.firstOrNull {
                manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == wanted
            } ?: manager.cameraIdList.firstOrNull()
        } catch (e: Exception) {
            Log.e(TAG, "cameraIdList failed", e)
            null
        }
    }

    fun hasMultipleCameras(): Boolean {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        return try {
            manager.cameraIdList.size > 1
        } catch (e: Exception) {
            false
        }
    }

    private companion object {
        private const val VIDEO_TRACK = 0
        private const val AUDIO_TRACK = 0
        private val TAG = CameraEncodeSession::class.java.simpleName
    }
}
