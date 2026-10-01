package com.example.stream_phone_cam

import android.app.Activity
import android.media.projection.MediaProjection
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Dart-facing plumbing for the publisher and the camera capture layer, in the
 * one-MethodChannel-plus-one-EventChannel shape the screencast feature
 * established (`com.streamphonecam/<feature>` + `<feature>_events`).
 *
 * Two channel pairs, one service: `publisher` drives and reports the
 * publishing legs, `camera` drives and reports the preview. They are separate
 * because the preview has its own lifecycle — it runs whenever the user is
 * looking at camera mode, whether or not anything is being published.
 *
 * Both `onListen` handlers push the current state immediately, covering the
 * race where the service is already running (a stream in progress from before
 * this engine existed) by the time Dart subscribes — the same guard
 * `MainActivity` applies to the screencast channel.
 */
class PublisherChannel(
    private val activity: Activity,
    private val serviceProvider: () -> PublisherForegroundService?,
    private val projectionProvider: () -> MediaProjection?,
) {
    private var publisherSink: EventChannel.EventSink? = null
    private var cameraSink: EventChannel.EventSink? = null
    private var textureRegistry: TextureRegistry? = null

    fun register(messenger: BinaryMessenger, registry: TextureRegistry) {
        textureRegistry = registry

        MethodChannel(messenger, PUBLISHER_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            val service = serviceProvider()
            when (call.method) {
                "start" -> {
                    @Suppress("UNCHECKED_CAST")
                    val request = call.arguments as? Map<String, Any?>
                    if (service == null || request == null) {
                        result.error("unavailable", "Publisher service is not bound yet.", null)
                    } else {
                        // The publishing foreground service and the
                        // connection-lost alert both need this on API 33+.
                        NotificationPermission.requestIfNeeded(activity)
                        service.start(request, projectionProvider())
                        result.success(null)
                    }
                }

                "stop" -> {
                    service?.stop()
                    result.success(null)
                }

                "setMuted" -> {
                    service?.setMuted(call.argument<Boolean>("muted") == true)
                    result.success(null)
                }

                "setQualityCeiling" -> {
                    service?.setQualityCeiling(
                        call.argument<Double>("scale") ?: 1.0,
                        call.argument<Int>("frameRateCap") ?: 0,
                    )
                    result.success(null)
                }

                "getStatus" -> result.success(service?.currentStatusMap() ?: mapOf("status" to "idle"))

                "supportedCodecs" -> result.success(PublisherForegroundService.supportedCodecs())

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, PUBLISHER_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    publisherSink = sink
                    serviceProvider()?.let { sink?.success(it.currentStatusMap()) }
                }

                override fun onCancel(arguments: Any?) {
                    publisherSink = null
                }
            },
        )

        MethodChannel(messenger, CAMERA_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            val service = serviceProvider()
            val registryForCall = textureRegistry
            when (call.method) {
                "startPreview" -> {
                    if (service == null || registryForCall == null) {
                        result.error("unavailable", "Publisher service is not bound yet.", null)
                    } else {
                        service.startCameraPreview(
                            registryForCall,
                            front = call.argument<Boolean>("front") ?: service.isLensFacingFront,
                            width = call.argument<Int>("width") ?: DEFAULT_WIDTH,
                            height = call.argument<Int>("height") ?: DEFAULT_HEIGHT,
                        ) { result.success(it) }
                    }
                }

                "switchCamera" -> {
                    if (service == null || registryForCall == null) {
                        result.error("unavailable", "Publisher service is not bound yet.", null)
                    } else {
                        service.startCameraPreview(
                            registryForCall,
                            front = !service.isLensFacingFront,
                            width = call.argument<Int>("width") ?: DEFAULT_WIDTH,
                            height = call.argument<Int>("height") ?: DEFAULT_HEIGHT,
                        ) { result.success(it) }
                    }
                }

                // Leaving camera mode releases the camera only when nothing is
                // being published; the service decides, since only it knows
                // whether a stream is live. Resolved from stopCameraPreviewIfIdle's
                // onDone callback — not synchronously here — so a caller that
                // awaits this actually gets a "camera is free now" signal
                // rather than just "the request was sent" (see that method's
                // doc comment).
                "stopPreview" -> {
                    val svc = service
                    if (svc == null) {
                        result.success(null)
                    } else {
                        svc.stopCameraPreviewIfIdle { result.success(null) }
                    }
                }

                "getStatus" -> result.success(
                    service?.currentCameraStatusMap() ?: mapOf("status" to "idle"),
                )

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, CAMERA_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    cameraSink = sink
                    serviceProvider()?.let { sink?.success(it.currentCameraStatusMap()) }
                }

                override fun onCancel(arguments: Any?) {
                    cameraSink = null
                }
            },
        )
    }

    /**
     * Wires this engine's sinks to a freshly bound service and re-points a
     * still-running preview at a texture this engine owns — a texture entry is
     * only valid for the registry that created it, so one from a previous
     * engine cannot be reused.
     */
    fun onServiceConnected(service: PublisherForegroundService) {
        service.onEvent = { map -> activity.runOnUiThread { publisherSink?.success(map) } }
        service.onCameraEvent = { map -> activity.runOnUiThread { cameraSink?.success(map) } }

        if (service.isPreviewRunning) {
            textureRegistry?.let { registry ->
                service.attachPreview(registry) { textureId ->
                    activity.runOnUiThread {
                        cameraSink?.success(service.currentCameraStatusMap().toMutableMap().apply {
                            this["textureId"] = textureId
                        })
                    }
                }
            }
        }
        publisherSink?.success(service.currentStatusMap())
    }

    private companion object {
        private const val PUBLISHER_METHOD_CHANNEL = "com.streamphonecam/publisher"
        private const val PUBLISHER_EVENT_CHANNEL = "com.streamphonecam/publisher_events"
        private const val CAMERA_METHOD_CHANNEL = "com.streamphonecam/camera"
        private const val CAMERA_EVENT_CHANNEL = "com.streamphonecam/camera_events"
        private const val DEFAULT_WIDTH = 1920
        private const val DEFAULT_HEIGHT = 1080
    }
}
