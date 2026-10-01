package com.haishinkit.gles.screen

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.opengl.GLES20
import android.opengl.GLES30
import android.view.Choreographer
import androidx.core.graphics.createBitmap
import com.haishinkit.gles.Framebuffer
import com.haishinkit.gles.GraphicsContext
import com.haishinkit.gles.Utils
import com.haishinkit.lang.Running
import com.haishinkit.media.source.VideoSource
import com.haishinkit.screen.ScreenObject
import com.haishinkit.screen.VideoScreenObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

internal class Screen(
    applicationContext: Context,
) : com.haishinkit.screen.Screen(applicationContext),
    Running,
    Choreographer.FrameCallback {
    val graphicsContext: GraphicsContext by lazy { GraphicsContext() }

    private var textureIds = intArrayOf(0)

    override var textureId: Int
        get() = framebuffer.textureId
        set(value) {
        }

    // StreamPhoneCam local patch — see PATCH_NOTES.md's "Producer/consumer
    // fence sync" section and the doc comment on the abstract property this
    // overrides. @Volatile because, unlike textureId (a rarely-changing int
    // that's fine to read "eventually consistent"), this one is read from
    // consumer threads specifically to establish a happens-before
    // relationship with this frame's write — a torn/stale 64-bit read here
    // would defeat the whole point.
    @Volatile
    override var textureFenceSync: Long = 0L

    override var frame: Rect
        get() = super.frame
        set(value) {
            super.frame = value
            framebuffer.bounds = value
        }

    override val isRunning: AtomicBoolean = AtomicBoolean(false)

    private val renderer: Renderer by lazy { Renderer(applicationContext) }
    private val framebuffer: Framebuffer by lazy { Framebuffer() }
    private var choreographer: Choreographer? = null
        set(value) {
            field?.removeFrameCallback(this)
            field = value
            field?.postFrameCallback(this)
        }
    private var videoTextureRegistry: VideoTextureRegistry = VideoTextureRegistry()

    override fun bind(screenObject: ScreenObject) {
        when (screenObject) {
            is VideoScreenObject -> {
                val track = screenObject.track
                videoTextureRegistry.getTextureIdByTrack(track)?.let { id ->
                    screenObject.textureId = id
                }
            }

            else -> {
                GLES20.glGenTextures(1, textureIds, 0)
                screenObject.textureId = textureIds[0]
            }
        }
    }

    override fun unbind(screenObject: ScreenObject) {
        when (screenObject) {
            is VideoScreenObject -> {
                screenObject.textureId = 0
            }

            else -> {
                textureIds[0] = screenObject.textureId
                GLES20.glDeleteTextures(1, textureIds, 0)
                screenObject.textureId = 0
            }
        }
    }

    override fun attachVideo(
        track: Int,
        video: VideoSource?,
    ) {
        if (video == null) {
            videoTextureRegistry.unregister(track)
        } else {
            videoTextureRegistry.register(track, video)
            videoTextureRegistry.getTextureIdByTrack(track)?.let { id ->
                findByClass(VideoScreenObject::class.java).forEach {
                    if (it.track == track) {
                        it.textureId = id
                        it.videoSize = video.videoSize
                        it.imageOrientation = video.imageOrientation
                    }
                }
            }
        }
    }

    override fun readPixels(lambda: (bitmap: Bitmap?) -> Unit) {
        val bitmap =
            createBitmap(frame.width(), frame.height())
        val byteBuffer =
            ByteBuffer.allocateDirect(frame.width() * frame.height() * 4).apply {
                order(ByteOrder.LITTLE_ENDIAN)
            }
        framebuffer.render {
            graphicsContext.readPixels(frame.width(), frame.height(), byteBuffer)
        }
        bitmap.copyPixelsFromBuffer(byteBuffer)
        lambda(
            Bitmap.createBitmap(
                bitmap,
                0,
                0,
                frame.width(),
                frame.height(),
                null,
                false,
            ),
        )
    }

    override fun dispose() {
        stopRunning()
        super.dispose()
    }

    override fun startRunning() {
        if (isRunning.get()) return
        isRunning.set(true)
        graphicsContext.open(null)
        // StreamPhoneCam local patch — see PATCH_NOTES.md and
        // GraphicsContext.createPbufferSurface's doc comment. Was
        // `graphicsContext.makeCurrent(null)` (a surfaceless context);
        // a real (if tiny) pbuffer surface gives this thread's default
        // framebuffer a valid backing on drivers that mishandle
        // EGL_KHR_surfaceless_context.
        graphicsContext.makeCurrent(graphicsContext.createPbufferSurface(PBUFFER_WIDTH, PBUFFER_HEIGHT))
        choreographer = Choreographer.getInstance()
    }

    override fun stopRunning() {
        if (!isRunning.get()) return
        isRunning.set(false)
        choreographer = null
        if (textureFenceSync != 0L) {
            GLES30.glDeleteSync(textureFenceSync)
            textureFenceSync = 0L
        }
        framebuffer.release()
        renderer.release()
        graphicsContext.close()
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (isRunning.get()) {
            for (callback in callbacks) {
                callback.onEnterFrame()
            }
            choreographer?.postFrameCallback(this)
        }

        if (!framebuffer.isEnabled) return

        layout(renderer)
        framebuffer.render {
            GLES20.glClearColor(
                (Color.red(backgroundColor) / 255).toFloat(),
                (Color.green(backgroundColor) / 255).toFloat(),
                (Color.blue(backgroundColor) / 255).toFloat(),
                0f,
            )
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            draw(renderer)
            GLES20.glDisable(GLES20.GL_BLEND)
        }

        // StreamPhoneCam local patch — see PATCH_NOTES.md's "Producer/
        // consumer fence sync" section. Marks the point in *this* context's
        // command stream after which textureId's content from the render
        // just above is complete, so a consumer on another (share-grouped)
        // context/thread can order its own read against it via
        // GLES30.glWaitSync instead of racing it.
        //
        // Order matters here: create-and-publish the new fence *before*
        // deleting the previous one. Per the GLES spec, a name is no longer
        // valid the instant glDeleteSync is called on it (the underlying
        // sync object itself is kept alive until signaled, but the client
        // name is not) — deleting first would leave a window where the
        // volatile field a consumer thread reads still holds that
        // already-invalid handle. Publishing the new fence first means the
        // field only ever transitions between two valid handles.
        // glFenceSync/glWaitSync are GLES3 core (no extension), but
        // GraphicsContext.open() falls back to a GLES2 context on a device
        // that can't negotiate GLES3 — guard against calling an ES3-only
        // function on one of those, which classic OpenGL ES only defines as
        // returning an error, but isn't a risk worth taking on unknown
        // driver behavior.
        if (graphicsContext.version >= 3) {
            val previousTextureFenceSync = textureFenceSync
            textureFenceSync = GLES30.glFenceSync(GLES30.GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
            if (previousTextureFenceSync != 0L) {
                GLES30.glDeleteSync(previousTextureFenceSync)
            }
        }

        GLES20.glFlush()
        Utils.checkGlError("glFlush")
    }

    companion object {
        @Suppress("unused")
        private val TAG = Screen::class.java.simpleName

        // StreamPhoneCam local patch — see startRunning()'s doc comment and
        // GraphicsContext.createPbufferSurface. Never actually rendered to
        // (this context only ever draws into Framebuffer's FBO) so its size
        // is irrelevant beyond "large enough for EGL to accept" — 1x1 is the
        // conventional minimum for a dummy pbuffer used this way.
        private const val PBUFFER_WIDTH = 1
        private const val PBUFFER_HEIGHT = 1
    }
}
