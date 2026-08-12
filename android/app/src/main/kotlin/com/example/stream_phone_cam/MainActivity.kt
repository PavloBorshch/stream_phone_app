package com.example.stream_phone_cam

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.streamphonecam/screencast"
    private val eventChannelName = "com.streamphonecam/screencast_events"
    private val captureRequestCode = 4201
    private val notificationPermissionRequestCode = 4202

    private var textureRegistry: TextureRegistry? = null
    private var service: ScreenCaptureForegroundService? = null
    private var eventSink: EventChannel.EventSink? = null

    /**
     * A capture grant that arrived before [connection] finished binding
     * (bindService() is async, so this is possible in principle even though
     * the consent dialog round-trip usually gives it plenty of time).
     * Consumed as soon as the service connects instead of being silently
     * dropped.
     */
    private var pendingCaptureResult: Intent? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val bound = (binder as ScreenCaptureForegroundService.LocalBinder).service
            service = bound
            bound.onEvent = { map -> runOnUiThread { eventSink?.success(map) } }

            // The service may already be capturing from before this Activity/engine
            // existed (e.g. the app was closed and reopened) - reattach a fresh
            // texture for the current engine so the live preview resumes.
            if (bound.isCapturing) {
                textureRegistry?.let { bound.attachTexture(it) }
            }

            pendingCaptureResult?.let { data ->
                pendingCaptureResult = null
                textureRegistry?.let { registry -> bound.startProjection(Activity.RESULT_OK, data, registry) }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        textureRegistry = flutterEngine.renderer

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCapture" -> {
                        requestNotificationPermissionIfNeeded()
                        launchCaptureIntent()
                        result.success(null)
                    }
                    "stopCapture" -> {
                        service?.stopProjection()
                        result.success(null)
                    }
                    "getStatus" -> result.success(service?.currentStatusMap() ?: mapOf("status" to "idle"))
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                        eventSink = sink
                        // Covers the case where the service already reattached (see
                        // onServiceConnected above) before Dart started listening.
                        service?.let { sink?.success(it.currentStatusMap()) }
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                },
            )

        bindService(
            Intent(this, ScreenCaptureForegroundService::class.java),
            connection,
            Context.BIND_AUTO_CREATE,
        )
    }

    private fun launchCaptureIntent() {
        val projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        eventSink?.success(mapOf("status" to "requesting"))
        startActivityForResult(projectionManager.createScreenCaptureIntent(), captureRequestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == captureRequestCode) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                ContextCompat.startForegroundService(
                    this,
                    Intent(this, ScreenCaptureForegroundService::class.java),
                )
                val bound = service
                if (bound != null) {
                    textureRegistry?.let { registry -> bound.startProjection(resultCode, data, registry) }
                } else {
                    pendingCaptureResult = data
                }
            } else {
                eventSink?.success(mapOf("status" to "denied"))
            }
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        unbindService(connection)
        super.onDestroy()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
        }
    }
}
