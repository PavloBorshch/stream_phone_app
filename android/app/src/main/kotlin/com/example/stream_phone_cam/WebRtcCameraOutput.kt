package com.example.stream_phone_cam

import android.content.Context
import android.util.Log
import android.util.Size
import android.view.Surface
import com.cloudwebrtc.webrtc.utils.EglUtils
import com.haishinkit.graphics.PixelTransform
import com.haishinkit.graphics.VideoGravity
import com.haishinkit.graphics.effect.DefaultVideoEffect
import com.haishinkit.graphics.effect.VideoEffect
import com.haishinkit.media.MediaBuffer
import com.haishinkit.media.MediaOutputDataSource
import com.haishinkit.view.StreamView
import org.webrtc.PeerConnectionFactory
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoTrack
import java.lang.ref.WeakReference

/**
 * PLAN.md §1.5 "Leg A": feeds the same composited camera/screencast frame
 * every RTMP leg encodes into a WebRTC [VideoTrack], so a paired PC can
 * receive it over the WebRTC connection Phase 4 already negotiates. See
 * HELP.md §8's "Leg A media track" section for the protocol this
 * implements, and PLAN.md Phase 5's "Outstanding" note for what's still
 * missing (no audio — see this class's own note below — and nothing on the
 * PC side can receive this yet).
 *
 * This is [FlutterTexturePreview]'s structure exactly (same [PixelTransform]
 * driving a plain Android [Surface]) with the destination swapped: instead
 * of a Flutter [io.flutter.view.TextureRegistry] texture, frames land on an
 * `org.webrtc.SurfaceTextureHelper`-owned surface, which converts them to
 * [org.webrtc.VideoFrame]s and hands them to a [org.webrtc.VideoSource]'s
 * [org.webrtc.CapturerObserver] directly — no [org.webrtc.VideoCapturer] is
 * needed since we already have decoded frames, not a camera to poll.
 *
 * Uses [EglUtils.getRootEglBaseContext] — the same shared root EGL context
 * flutter_webrtc's own rendering uses — rather than creating a second GL
 * context, exactly as recommended for any additional WebRTC-side GL consumer
 * in the same process.
 *
 * **No audio.** Unlike the RTMP legs, this track is video-only. libwebrtc's
 * Android `AudioSource` is driven entirely by its configured
 * `AudioDeviceModule` (normally the microphone) with no public API to push
 * externally-mixed PCM samples in, unlike `VideoSource`'s explicit
 * external-frame support — bridging HaishinKit's mixed audio into it would
 * need a custom `AudioDeviceModule`, real additional work tracked in
 * PLAN.md rather than attempted here.
 */
class WebRtcCameraOutput(
    context: Context,
    factory: PeerConnectionFactory,
    width: Int,
    height: Int,
) : StreamView {
    override var dataSource: WeakReference<MediaOutputDataSource>? = null
        set(value) {
            field = value
            pixelTransform.screen = value?.get()?.screen
        }

    override var videoGravity: VideoGravity
        get() = pixelTransform.videoGravity
        set(value) {
            pixelTransform.videoGravity = value
        }

    override var frameRate: Int
        get() = pixelTransform.frameRate
        set(value) {
            pixelTransform.frameRate = value
        }

    override var videoEffect: VideoEffect
        get() = pixelTransform.videoEffect
        set(value) {
            pixelTransform.videoEffect = value
        }

    /** Track id flutter_webrtc's local-track registry keys on; see [track]. */
    val trackId: String get() = track.id()

    private val pixelTransform: PixelTransform by lazy { PixelTransform.create(context) }
    private val surfaceTextureHelper: SurfaceTextureHelper =
        SurfaceTextureHelper.create("WebRtcCameraOutput", EglUtils.getRootEglBaseContext())
    private var deliveredFrames = 0L
    private var lastLoggedSize: Pair<Int, Int>? = null
    private val videoSource = factory.createVideoSource(false)
    private val surface: Surface

    /**
     * The track native code hands to `FlutterWebRTCPlugin.attachExternalTrack`
     * (the local patch — see `third_party/flutter_webrtc/PATCH_NOTES.md`).
     */
    val track: VideoTrack = factory.createVideoTrack("phoneCamLegAVideo", videoSource)

    init {
        setTextureSize(width, height)
        surface = Surface(surfaceTextureHelper.surfaceTexture)
        pixelTransform.videoGravity = VideoGravity.RESIZE_ASPECT_FILL
        pixelTransform.videoEffect = DefaultVideoEffect.shared
        pixelTransform.imageExtent = Size(width, height)
        pixelTransform.surface = surface

        // Started before startListening, not after: the helper delivers on
        // its own thread as soon as it has a listener, and a frame that
        // reaches an un-started CapturerObserver is discarded.
        videoSource.capturerObserver.onCapturerStarted(true)
        // No frame.release() here on purpose -- SurfaceTextureHelper
        // releases its own reference after this callback returns, and
        // dropping an extra one would under-count the texture's refs. Same
        // shape as OrientationAwareScreenCapturer.onFrame in the vendored
        // flutter_webrtc fork.
        surfaceTextureHelper.startListening { frame ->
            countFrame(frame)
            videoSource.capturerObserver.onFrameCaptured(frame)
        }
        track.setEnabled(true)
        Log.i(TAG, "Leg A video output started: ${width}x$height, track=${track.id()}")
    }

    /** The preview is display-only; encoded buffers are of no interest here. */
    override fun append(buffer: MediaBuffer) = Unit

    fun setExtent(width: Int, height: Int) {
        setTextureSize(width, height)
        pixelTransform.imageExtent = Size(width, height)
    }

    /**
     * Sizes both halves of the [SurfaceTextureHelper] handoff — the
     * `SurfaceTexture`'s buffer (what [PixelTransform] renders into) *and*
     * the helper's own texture dimensions.
     *
     * The second one is not optional and is not implied by the first.
     * `SurfaceTextureHelper.tryDeliverTextureFrame()` returns early — before
     * it ever calls `updateTexImage()` — while its texture size is still
     * unset, logging `W/SurfaceTextureHelper: Texture size has not been
     * set.`. So without [SurfaceTextureHelper.setTextureSize] nothing ever
     * *consumes* the SurfaceTexture: every frame HaishinKit renders piles up
     * in the BufferQueue and is dropped (`I/BufferQueueProducer: queueBuffer:
     * slot N is dropped` on repeat in logcat), the [videoSource] is never
     * fed a single frame, and a paired PC sees Leg A's video track negotiate
     * successfully and then sit at zero decoded frames forever — with the
     * audio track, which never touches this path, working perfectly and so
     * making it look like a PC-side receive problem.
     *
     * [FlutterTexturePreview] gets away with `setDefaultBufferSize` alone
     * because Flutter's `TextureRegistry` is the consumer there and drains
     * the SurfaceTexture itself; transposing that class to a WebRTC sink
     * (see this class's header) is exactly where the extra call is needed.
     * `OrientationAwareScreenCapturer.updateSurfaceTextureSize()` in the
     * vendored flutter_webrtc fork pairs the two calls for the same reason.
     */
    private fun setTextureSize(width: Int, height: Int) {
        // Coerced, not asserted: setTextureSize throws on a non-positive
        // dimension, and this runs from the constructor — a zero slipping
        // through from the publish request would turn "a video track that
        // sends nothing" into "no video track at all", which is strictly
        // less debuggable.
        val w = width.coerceAtLeast(2)
        val h = height.coerceAtLeast(2)
        if (w != width || h != height) {
            Log.w(TAG, "Leg A: non-positive extent ${width}x$height, using ${w}x$h")
        }
        surfaceTextureHelper.setTextureSize(w, h)
        surfaceTextureHelper.surfaceTexture.setDefaultBufferSize(w, h)
    }

    /**
     * Logs the first frame the [SurfaceTextureHelper] actually delivers,
     * and then a periodic heartbeat.
     *
     * This is the one fact that splits a stalled Leg A in half. Everything
     * before it — the track existing, `addTrack` succeeding, the PC
     * answering the renegotiation, the PC attaching its capture sink — is
     * equally true whether this callback fires once or never, so a PC tile
     * stuck on "Video Starting..." says nothing about which side is at
     * fault. If this logs, the phone is feeding libwebrtc and the problem
     * is encode/transport/PC-side; if it never logs, nothing downstream can
     * possibly help.
     */
    private fun countFrame(frame: org.webrtc.VideoFrame) {
        deliveredFrames++
        // First frame and size changes only. A periodic heartbeat was the
        // obvious thing to add here, but logcat on this hardware is already
        // hard to read through the driver's own output, and "did anything
        // ever arrive, and at what size" is the entire diagnostic value —
        // a rate is visible from the PC's WebRTC stats instead.
        val size = frame.buffer.width to frame.buffer.height
        if (deliveredFrames == 1L || size != lastLoggedSize) {
            lastLoggedSize = size
            Log.i(
                TAG,
                "Leg A: delivered frame #$deliveredFrames " +
                    "${size.first}x${size.second} rot=${frame.rotation}",
            )
        }
    }

    /**
     * Torn down producer-first: HaishinKit is detached from the [Surface]
     * before the [SurfaceTextureHelper] that owns the SurfaceTexture behind
     * it goes away, and the Surface itself outlives both. The reverse order
     * leaves [PixelTransform] rendering into a Surface whose SurfaceTexture
     * has already been disposed.
     */
    fun release() {
        pixelTransform.surface = null
        pixelTransform.screen = null

        track.setEnabled(false)
        track.dispose()
        videoSource.capturerObserver.onCapturerStopped()
        videoSource.dispose()

        surfaceTextureHelper.stopListening()
        surfaceTextureHelper.dispose()
        surface.release()
    }

    private companion object {
        private const val TAG = "WebRtcCameraOutput"
    }
}
