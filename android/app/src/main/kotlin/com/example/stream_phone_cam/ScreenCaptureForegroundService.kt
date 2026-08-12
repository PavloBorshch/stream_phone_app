package com.example.stream_phone_cam

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Surface
import androidx.core.app.NotificationCompat
import io.flutter.view.TextureRegistry

/**
 * Owns the MediaProjection/VirtualDisplay for as long as the user keeps
 * screencasting, independent of the Flutter Activity/engine lifecycle - so
 * closing and reopening the app (or switching capture mode in the UI) does
 * not interrupt an in-progress screen capture. It only stops when the user
 * explicitly requests it, or the system itself stops the projection (e.g.
 * via the "Stop casting" control Android shows while a projection is
 * active).
 *
 * MainActivity binds to this service (same process, so a simple local
 * Binder is enough) rather than owning the capture objects itself, because
 * the Activity/FlutterEngine can be destroyed and recreated (e.g. the user
 * backs out and reopens the app) while this service keeps running. When a
 * new engine attaches, [attachTexture] re-points the still-running
 * VirtualDisplay at a freshly registered texture for that engine via
 * [VirtualDisplay.setSurface], since a texture entry only remains valid for
 * the FlutterEngine/TextureRegistry that created it.
 */
class ScreenCaptureForegroundService : Service() {

    inner class LocalBinder : Binder() {
        val service: ScreenCaptureForegroundService get() = this@ScreenCaptureForegroundService
    }

    private val binder = LocalBinder()

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var width = 0
    private var height = 0
    private var densityDpi = 0

    /** Latest listener - swapped out each time a new Activity/engine binds. */
    var onEvent: ((Map<String, Any?>) -> Unit)? = null

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            releaseProjection()
            onEvent?.invoke(mapOf("status" to "stopped"))
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()
        return START_NOT_STICKY
    }

    /**
     * Promotes this service to the foreground, showing the ongoing-capture
     * notification. Safe to call more than once (just reapplies the same
     * notification). Called both from [onStartCommand] (in case the OS
     * (re)starts this service on its own) and synchronously at the top of
     * [startProjection] - the latter is required, not just defensive: on
     * Android 14+ [MediaProjectionManager.getMediaProjection] throws unless
     * a "mediaProjection"-type foreground service is *already* active at the
     * moment it's called, and `ContextCompat.startForegroundService()` only
     * posts an async request whose [onStartCommand] dispatch isn't
     * guaranteed to have run yet by the time the caller's next line
     * executes.
     */
    private fun promoteToForeground() {
        val channelId = "screencast_capture"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Screen capture",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Screen capture active")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    val isCapturing: Boolean get() = mediaProjection != null

    /** Starts a brand new capture session from a freshly granted consent result. */
    fun startProjection(resultCode: Int, data: Intent, textureRegistry: TextureRegistry) {
        promoteToForeground()

        val projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = projectionManager.getMediaProjection(resultCode, data)
        if (projection == null) {
            onEvent?.invoke(mapOf("status" to "error", "message" to "getMediaProjection failed"))
            return
        }

        mediaProjection = projection
        projection.registerCallback(projectionCallback, Handler(Looper.getMainLooper()))

        val metrics = resources.displayMetrics
        width = metrics.widthPixels
        height = metrics.heightPixels
        densityDpi = metrics.densityDpi

        onEvent?.invoke(mapOf("status" to "starting"))
        attachTexture(textureRegistry)
    }

    /**
     * Registers a fresh texture against [textureRegistry] and points the
     * capture output at it. Safe to call repeatedly: if a VirtualDisplay
     * already exists (a still-running capture reattaching to a new engine),
     * its surface is swapped in place rather than recreated.
     */
    fun attachTexture(textureRegistry: TextureRegistry) {
        val projection = mediaProjection ?: return

        surfaceTextureEntry?.release()
        val entry = textureRegistry.createSurfaceTexture()
        entry.surfaceTexture().setDefaultBufferSize(width, height)
        surfaceTextureEntry = entry
        val surface = Surface(entry.surfaceTexture())

        val existingDisplay = virtualDisplay
        if (existingDisplay != null) {
            existingDisplay.setSurface(surface)
        } else {
            virtualDisplay = projection.createVirtualDisplay(
                "ScreencastCapture",
                width,
                height,
                densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                surface,
                null,
                null,
            )
        }

        onEvent?.invoke(currentStatusMap())
    }

    fun stopProjection() {
        releaseProjection()
        stopForeground(STOP_FOREGROUND_REMOVE)
        onEvent?.invoke(mapOf("status" to "stopped"))
    }

    fun currentStatusMap(): Map<String, Any?> {
        val entry = surfaceTextureEntry
        return when {
            mediaProjection == null -> mapOf("status" to "idle")
            entry == null -> mapOf("status" to "starting")
            else -> mapOf(
                "status" to "capturing",
                "textureId" to entry.id(),
                "width" to width,
                "height" to height,
            )
        }
    }

    private fun releaseProjection() {
        virtualDisplay?.release()
        virtualDisplay = null
        mediaProjection?.unregisterCallback(projectionCallback)
        mediaProjection?.stop()
        mediaProjection = null
        surfaceTextureEntry?.release()
        surfaceTextureEntry = null
    }

    override fun onDestroy() {
        releaseProjection()
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_ID = 1
    }
}
