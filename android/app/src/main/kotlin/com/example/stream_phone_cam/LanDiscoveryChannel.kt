package com.example.stream_phone_cam

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Browses for PCs advertising `_streamphonecam._tcp` on the LAN (see
 * HELP.md's "LAN discovery" section) via Android's NsdManager. This app
 * never advertises itself — only browses — so there is no NsdManager
 * `registerService` call here, only `discoverServices`/`resolveService`.
 *
 * Not a bound foreground Service like [ScreenCaptureForegroundService]:
 * discovery only needs to run while a pairing screen is open, so its
 * lifetime is tied directly to this channel object rather than surviving
 * Activity/engine teardown.
 */
class LanDiscoveryChannel(private val context: Context) {
    companion object {
        private const val METHOD_CHANNEL_NAME = "com.streamphonecam/lan_discovery"
        private const val EVENT_CHANNEL_NAME = "com.streamphonecam/lan_discovery_events"
        private const val SERVICE_TYPE = "_streamphonecam._tcp."
    }

    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager?
    private var multicastLock: WifiManager.MulticastLock? = null

    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var eventSink: EventChannel.EventSink? = null

    /** Services currently known-found, replayed to a new [EventChannel] listener. */
    private val knownServices = mutableMapOf<String, Map<String, Any?>>()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBrowse" -> {
                    startBrowse()
                    result.success(null)
                }
                "stopBrowse" -> {
                    stopBrowse()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL_NAME).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    // Replay everything already known, same race-cover pattern as
                    // ScreencastChannel/MainActivity's screencast EventChannel.
                    knownServices.values.forEach { sink?.success(it) }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    private fun startBrowse() {
        if (discoveryListener != null) return

        multicastLock = wifiManager?.createMulticastLock("com.streamphonecam.lan_discovery")?.apply {
            setReferenceCounted(true)
            acquire()
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String?) {}

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                resolve(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                val known = knownServices.remove(serviceInfo.serviceName)
                val pcId = known?.get("pcId") as? String ?: return
                eventSink?.success(known.toMutableMap().apply { put("type", "lost") })
                knownServices.remove(pcId)
            }

            override fun onDiscoveryStopped(serviceType: String?) {}

            override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
                eventSink?.success(mapOf("type" to "browseError", "message" to "startDiscoveryFailed: $errorCode"))
                discoveryListener = null
            }

            override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {
                discoveryListener = null
            }
        }
        discoveryListener = listener
        try {
            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: IllegalArgumentException) {
            // NsdManager can reject a discoverServices() call that races a just-issued
            // stopServiceDiscovery() from the previous startBrowse/stopBrowse cycle (its
            // teardown is async even though stopBrowse() clears our state synchronously).
            // Surface it as a browseError instead of letting it crash the app.
            discoveryListener = null
            if (multicastLock?.isHeld == true) multicastLock?.release()
            multicastLock = null
            eventSink?.success(mapOf("type" to "browseError", "message" to "discoverServices threw: ${e.message}"))
        }
    }

    private fun resolve(serviceInfo: NsdServiceInfo) {
        try {
            nsdManager.resolveService(
                serviceInfo,
                object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {}

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        val attrs = serviceInfo.attributes
                        fun attr(key: String): String? = attrs[key]?.let { String(it, Charsets.UTF_8) }

                        val pcId = attr("id") ?: return
                        val map = mapOf(
                            "type" to "found",
                            "pcId" to pcId,
                            "pcName" to (attr("name") ?: serviceInfo.serviceName),
                            "host" to serviceInfo.host.hostAddress,
                            "port" to serviceInfo.port,
                            "wsPath" to (attr("path") ?: "/pair"),
                        )
                        knownServices[serviceInfo.serviceName] = map
                        knownServices[pcId] = map
                        eventSink?.success(map)
                    }
                },
            )
        } catch (e: IllegalArgumentException) {
            // Same race as discoverServices() above - a resolve for a service found just
            // before a stopBrowse() can land after NsdManager considers it torn down.
        }
    }

    private fun stopBrowse() {
        discoveryListener?.let {
            try {
                nsdManager.stopServiceDiscovery(it)
            } catch (_: IllegalArgumentException) {
                // Already stopped/never started successfully - safe to ignore.
            }
        }
        discoveryListener = null
        knownServices.clear()
        if (multicastLock?.isHeld == true) multicastLock?.release()
        multicastLock = null
    }
}
