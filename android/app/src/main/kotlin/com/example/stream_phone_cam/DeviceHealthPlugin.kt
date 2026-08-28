package com.example.stream_phone_cam

import android.content.Context
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Reports device thermal state to Dart over
 * `com.streamphonecam/device_health` + `_events`, following the same
 * method-channel-plus-event-channel shape as the screencast and publisher
 * bridges.
 *
 * Thermal state has no Flutter plugin equivalent and cannot be inferred from
 * battery data — a phone can be cool at 20% battery and throttling hard at
 * 90% while charging — so it needs this native listener. Battery level itself
 * is *not* here: `battery_plus` already covers it (PLAN.md Phase 7), and
 * duplicating it natively would mean two sources of truth.
 *
 * `addThermalStatusListener` is API 29+. Below that the OS exposes no thermal
 * signal at all, so this reports [STATUS_UNKNOWN] rather than guessing — the
 * Dart side treats unknown as "don't throttle", since acting on a fabricated
 * reading would degrade quality for no reason.
 */
class DeviceHealthPlugin(private val context: Context) {
    private var eventSink: EventChannel.EventSink? = null
    private var listener: PowerManager.OnThermalStatusChangedListener? = null

    private val powerManager: PowerManager
        get() = context.getSystemService(Context.POWER_SERVICE) as PowerManager

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(currentStatusMap())
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    // The device may already be hot when Dart subscribes, and
                    // the listener only fires on *changes*, so the current
                    // value has to be pushed immediately.
                    sink?.success(currentStatusMap())
                    startListening()
                }

                override fun onCancel(arguments: Any?) {
                    stopListening()
                    eventSink = null
                }
            },
        )
    }

    private fun startListening() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || listener != null) return
        val created = PowerManager.OnThermalStatusChangedListener { status ->
            eventSink?.success(statusMap(status))
        }
        listener = created
        powerManager.addThermalStatusListener(created)
    }

    private fun stopListening() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        listener?.let { powerManager.removeThermalStatusListener(it) }
        listener = null
    }

    fun currentStatusMap(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return mapOf("thermalStatus" to STATUS_UNKNOWN)
        }
        return statusMap(powerManager.currentThermalStatus)
    }

    private fun statusMap(status: Int): Map<String, Any?> = mapOf("thermalStatus" to status)

    private companion object {
        private const val METHOD_CHANNEL = "com.streamphonecam/device_health"
        private const val EVENT_CHANNEL = "com.streamphonecam/device_health_events"

        /**
         * Matches `PowerManager.THERMAL_STATUS_NONE`'s absence rather than any
         * real constant: -1 is used for "this device cannot tell us".
         */
        private const val STATUS_UNKNOWN = -1
    }
}
