package com.example.stream_phone_cam

import android.content.Context
import android.util.Size
import android.view.Surface
import com.haishinkit.graphics.PixelTransform
import com.haishinkit.graphics.VideoGravity
import com.haishinkit.graphics.effect.DefaultVideoEffect
import com.haishinkit.graphics.effect.VideoEffect
import com.haishinkit.media.MediaBuffer
import com.haishinkit.media.MediaOutputDataSource
import com.haishinkit.view.StreamView
import io.flutter.view.TextureRegistry
import java.lang.ref.WeakReference

/**
 * Renders the [com.haishinkit.media.MediaMixer]'s composited output into a
 * Flutter texture, so the capture preview can be drawn by the Flutter widget
 * tree instead of an Android [android.view.View].
 *
 * This is the second output of the single capture session PLAN.md §1.4 calls
 * for: the mixer feeds the hardware encoder (via the registered
 * [com.haishinkit.stream.Stream]s) and this preview at the same time, from
 * one open camera. It is a direct transposition of HaishinKit's own
 * `HkTextureView` — same [PixelTransform] driving, with the `TextureView`'s
 * `SurfaceTexture` swapped for one registered against Flutter's
 * [TextureRegistry].
 *
 * A texture entry is only valid for the [io.flutter.embedding.engine.FlutterEngine]
 * that created it, so this object is recreated whenever a new engine
 * attaches — the same constraint `ScreenCaptureForegroundService` works
 * around with `VirtualDisplay.setSurface()`.
 */
class FlutterTexturePreview(
    context: Context,
    private val entry: TextureRegistry.SurfaceTextureEntry,
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

    val textureId: Long get() = entry.id()

    private val pixelTransform: PixelTransform by lazy { PixelTransform.create(context) }
    private val surface: Surface

    init {
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        surface = Surface(entry.surfaceTexture())
        pixelTransform.videoGravity = VideoGravity.RESIZE_ASPECT_FILL
        pixelTransform.videoEffect = DefaultVideoEffect.shared
        pixelTransform.imageExtent = Size(width, height)
        pixelTransform.surface = surface
    }

    /** The preview is display-only; encoded buffers are of no interest here. */
    override fun append(buffer: MediaBuffer) = Unit

    fun setExtent(width: Int, height: Int) {
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        pixelTransform.imageExtent = Size(width, height)
    }

    fun release() {
        pixelTransform.surface = null
        pixelTransform.screen = null
        surface.release()
        entry.release()
    }
}
