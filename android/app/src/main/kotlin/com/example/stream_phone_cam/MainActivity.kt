package com.example.stream_phone_cam

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
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

    private var textureRegistry: TextureRegistry? = null
    private var service: ScreenCaptureForegroundService? = null
    private var publisherService: PublisherForegroundService? = null
    private var eventSink: EventChannel.EventSink? = null

    // Phase 5's publisher/camera channels. Constructed lazily for the same
    // reason as lanDiscoveryChannel below.
    private var publisherChannel: PublisherChannel? = null

    private val publisherConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val bound = (binder as PublisherForegroundService.LocalBinder).service
            publisherService = bound
            publisherChannel?.onServiceConnected(bound)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            publisherService = null
        }
    }

    // Constructed lazily in configureFlutterEngine (not as an eager field
    // initializer) because it calls getSystemService(), which needs the
    // Activity's base Context already attached - not yet true during the
    // Activity's own construction.
    private var lanDiscoveryChannel: LanDiscoveryChannel? = null
    private var deviceHealthPlugin: DeviceHealthPlugin? = null

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
                        NotificationPermission.requestIfNeeded(this)
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

        val discoveryChannel = lanDiscoveryChannel ?: LanDiscoveryChannel(this).also { lanDiscoveryChannel = it }
        discoveryChannel.register(flutterEngine.dartExecutor.binaryMessenger)

        val publisher = publisherChannel ?: PublisherChannel(
            this,
            serviceProvider = { publisherService },
            // Screencast publishing borrows the projection the screencast
            // service already owns rather than asking the user to consent a
            // second time.
            projectionProvider = { service?.currentProjection },
        ).also { publisherChannel = it }
        publisher.register(flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)
        publisherService?.let { publisher.onServiceConnected(it) }

        bindService(
            Intent(this, PublisherForegroundService::class.java),
            publisherConnection,
            Context.BIND_AUTO_CREATE,
        )

        val deviceHealth = deviceHealthPlugin ?: DeviceHealthPlugin(this).also { deviceHealthPlugin = it }
        deviceHealth.register(flutterEngine.dartExecutor.binaryMessenger)
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
        unbindService(publisherConnection)
        super.onDestroy()
    }

}
