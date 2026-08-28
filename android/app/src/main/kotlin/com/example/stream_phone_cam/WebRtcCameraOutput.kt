package com.example.stream_phone_cam

import android.content.Context
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
    private val videoSource = factory.createVideoSource(false)
    private val surface: Surface

    /**
     * The track native code hands to `FlutterWebRTCPlugin.attachExternalTrack`
     * (the local patch — see `third_party/flutter_webrtc/PATCH_NOTES.md`).
     */
    val track: VideoTrack = factory.createVideoTrack("phoneCamLegAVideo", videoSource)

    init {
        surfaceTextureHelper.surfaceTexture.setDefaultBufferSize(width, height)
        surface = Surface(surfaceTextureHelper.surfaceTexture)
        pixelTransform.videoGravity = VideoGravity.RESIZE_ASPECT_FILL
        pixelTransform.videoEffect = DefaultVideoEffect.shared
        pixelTransform.imageExtent = Size(width, height)
        pixelTransform.surface = surface

        surfaceTextureHelper.startListening { frame -> videoSource.capturerObserver.onFrameCaptured(frame) }
        videoSource.capturerObserver.onCapturerStarted(true)
        track.setEnabled(true)
    }

    /** The preview is display-only; encoded buffers are of no interest here. */
    override fun append(buffer: MediaBuffer) = Unit

    fun setExtent(width: Int, height: Int) {
        surfaceTextureHelper.surfaceTexture.setDefaultBufferSize(width, height)
        pixelTransform.imageExtent = Size(width, height)
    }

    fun release() {
        track.setEnabled(false)
        track.dispose()
        videoSource.capturerObserver.onCapturerStopped()
        videoSource.dispose()
        surfaceTextureHelper.stopListening()
        surfaceTextureHelper.dispose()
        pixelTransform.surface = null
        pixelTransform.screen = null
        surface.release()
    }
}
