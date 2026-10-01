package com.example.stream_phone_cam

import android.content.pm.ApplicationInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.net.TrafficStats
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Process
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.haishinkit.codec.VideoCodecProfileLevel
import com.haishinkit.rtmp.RtmpStream
import com.haishinkit.rtmp.RtmpStreamSessionFactory
import com.haishinkit.stream.StreamSession
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.webrtc.Logging
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.MediaConstraints
import org.webrtc.PeerConnectionFactory

/**
 * Owns the capture session and every publishing leg, for as long as the user
 * keeps streaming — independent of the Flutter Activity/engine lifecycle, the
 * same arrangement (and for the same reason) as
 * `ScreenCaptureForegroundService`: the Activity can be destroyed and
 * recreated under a live stream, and tearing the encoder down with it would
 * drop the broadcast.
 *
 * `MainActivity` binds to this service rather than owning the capture objects
 * itself, and re-attaches a preview texture for each new engine (see
 * [attachPreview]).
 */
class PublisherForegroundService : Service() {

    inner class LocalBinder : Binder() {
        val service: PublisherForegroundService get() = this@PublisherForegroundService
    }

    /** One destination leg: its HaishinKit session plus what we report for it. */
    private class Leg(
        val destinationId: String,
        val displayName: String,
        /** The configured bitrate; adaptation scales [currentBitrateKbps] off this. */
        val bitrateKbps: Int,
        val session: StreamSession?,
        var status: String,
        var message: String? = null,
    ) {
        var currentBitrateKbps: Int = bitrateKbps
        var retries: Int = 0
        var nextRetryAtMs: Long = 0
    }

    private val binder = LocalBinder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var captureSession: CameraEncodeSession? = null
    private val legs = mutableListOf<Leg>()

    /** PLAN.md §1.5 "Leg A" — see [attachWebRtcLeg]'s doc comment. */
    private var webRtcLeg: WebRtcCameraOutput? = null
    private var webRtcPeerConnectionId: String? = null
    private var webRtcLoggingEnabled = false

    /**
     * Leg A's audio, independent of [webRtcLeg]: see [attachWebRtcAudio]'s
     * doc comment for why this is a second, entirely separate microphone
     * capture rather than fed from the same mixer the RTMP legs use.
     */
    private var webRtcAudioTrack: AudioTrack? = null
    private var webRtcAudioSource: AudioSource? = null

    /**
     * Mirrors the last value passed to [setMuted] — needed because Leg A's
     * audio track (a capture independent of [captureSession]'s mixer, see
     * [attachWebRtcAudio]) can be created *after* the user already muted, and
     * a freshly attached track must start in that same state.
     */
    private var isMuted: Boolean = false
    private var statsJob: Job? = null
    private var startedAtMs: Long = 0
    private var isPublishing = false
    private var usesProjection = false
    private var lastError: String? = null
    private val legFps = mutableMapOf<String, Int>()
    private var quality: NetworkQualityController? = null

    /** Guard ceiling requested before a session existed, applied on start. */
    private var pendingCeiling: Pair<Double, Int>? = null
    private var baseBitrateKbps: Int = DEFAULT_BITRATE_KBPS
    private var baseFrameRate: Int = 30

    /**
     * Transmit-byte counter reading at the moment publishing started. Bytes
     * are reported relative to it, so each session counts from zero.
     * [UNSUPPORTED_TX] means this device does not implement the counter, in
     * which case throughput cannot be measured and adaptation stays off.
     */
    private var txBytesAtStart: Long = UNSUPPORTED_TX
    private var lastTxBytes: Long = 0
    private var lastSampleAtMs: Long = 0
    private var measuredKbps: Int? = null
    private var bytesSent: Long = 0

    /** Latest listeners — swapped out each time a new Activity/engine binds. */
    var onEvent: ((Map<String, Any?>) -> Unit)? = null
    var onCameraEvent: ((Map<String, Any?>) -> Unit)? = null

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Only promoted to the foreground while actually publishing; as a
        // plain bound service it shows no notification, so a camera preview
        // costs the user nothing.
        if (isPublishing) promoteToForeground()
        return START_NOT_STICKY
    }

    private fun session(): CameraEncodeSession {
        return captureSession ?: CameraEncodeSession(applicationContext).also { captureSession = it }
    }

    // ---------------------------------------------------------------- preview

    /**
     * Starts (or switches) the camera preview and points it at a texture
     * belonging to [registry]. Returns the texture id for the Dart side.
     */
    fun startCameraPreview(
        registry: TextureRegistry,
        front: Boolean,
        width: Int,
        height: Int,
        onReady: (Long) -> Unit,
    ) {
        val capture = session()
        scope.launch {
            capture.startCamera(front, width, height)
            val textureId = capture.attachPreview(registry, width, height)
            onReady(textureId)
            emitCamera()
        }
    }

    /**
     * Re-attaches the preview to a new engine's texture registry without
     * touching the capture session — the running camera and any live
     * publishing legs are unaffected.
     */
    fun attachPreview(registry: TextureRegistry, onReady: (Long) -> Unit) {
        val capture = captureSession ?: return
        if (!capture.isRunning) return
        val textureId = capture.attachPreview(
            registry,
            capture.previewWidth.coerceAtLeast(DEFAULT_WIDTH),
            capture.previewHeight.coerceAtLeast(DEFAULT_HEIGHT),
        )
        onReady(textureId)
        emitCamera()
    }

    fun detachPreview() {
        captureSession?.detachPreview()
        emitCamera()
    }

    fun hasMultipleCameras(): Boolean = session().hasMultipleCameras()

    val isPreviewRunning: Boolean get() = captureSession?.isRunning == true

    val isLensFacingFront: Boolean get() = captureSession?.lensFacingFront == true

    /**
     * Stops the camera but only when nothing is being published — a live
     * stream must survive the preview pane unmounting (mode switch, app
     * backgrounded), which is the whole point of owning capture here.
     *
     * [onDone] runs once the release has actually finished — or
     * immediately, synchronously, if there was nothing to release or it was
     * declined — never merely once this call *returns*, since the real
     * teardown happens on [scope]'s coroutine. `PublisherChannel`'s
     * `stopPreview` handler resolves its Dart `Future` from here rather
     * than synchronously, precisely so a caller that needs the physical
     * camera genuinely free before doing something else with it (e.g.
     * `QrScanPage` borrowing it for `mobile_scanner` — see
     * `qr_scan_page.dart`'s doc comment) can `await` a real signal instead
     * of a same-thread "request sent" acknowledgement.
     */
    fun stopCameraPreviewIfIdle(onDone: () -> Unit = {}) {
        if (isPublishing) {
            onDone()
            return
        }
        val capture = captureSession ?: run {
            onDone()
            return
        }
        captureSession = null
        scope.launch {
            capture.release()
            emitCamera()
            onDone()
        }
    }

    // ------------------------------------------------------------- publishing

    /**
     * Starts publishing [request] to every leg it names. [projection] is
     * required only for `source == "screencast"` and is borrowed from
     * `ScreenCaptureForegroundService`, never owned here.
     */
    fun start(request: Map<String, Any?>, projection: MediaProjection?) {
        if (isPublishing) return

        // A failed start leaves its legs in place so the UI can still show
        // which destination refused and why; they are only discarded here,
        // when a new attempt begins. Without this, a retry would append to the
        // previous attempt's list and publish to phantom destinations.
        legs.clear()
        legFps.clear()

        val video = request["video"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val audio = request["audio"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val source = request["source"] as? String ?: "camera"
        val rawLegs = request["legs"] as? List<*> ?: emptyList<Any?>()

        val width = (video["width"] as? Int) ?: DEFAULT_WIDTH
        val height = (video["height"] as? Int) ?: DEFAULT_HEIGHT
        val fps = (video["fps"] as? Int) ?: 30
        val codec = (video["codec"] as? String) ?: "h264"
        val sampleRate = (audio["sampleRate"] as? Int) ?: 48000
        val channelCount = (audio["channels"] as? Int) ?: 2
        val audioBitrateKbps = (audio["bitrateKbps"] as? Int) ?: 128

        usesProjection = source == "screencast"
        isPublishing = true
        lastError = null
        startedAtMs = SystemClock.elapsedRealtime()
        beginMeasuring()
        baseBitrateKbps = (video["bitrateKbps"] as? Int) ?: DEFAULT_BITRATE_KBPS
        baseFrameRate = fps
        quality = if (video["adaptive"] as? Boolean != false) {
            NetworkQualityController(baseBitrateKbps, baseFrameRate)
        } else {
            null
        }
        pendingCeiling?.let { (scale, cap) -> quality?.setCeiling(scale, cap) }
        promoteToForeground()
        emit(currentStatusMap())

        scope.launch {
            val capture = session()
            if (usesProjection) {
                if (projection == null) {
                    fail("Screen capture is not running — start it before streaming.")
                    return@launch
                }
                capture.startScreencast(projection)
            } else {
                capture.startCamera(capture.lensFacingFront, width, height)
            }
            capture.startMicrophone(sampleRate)

            for (raw in rawLegs) {
                val map = raw as? Map<*, *> ?: continue
                legs.add(buildLeg(map, width, height, fps, codec, sampleRate, channelCount, audioBitrateKbps))
            }

            // Attached before either "is there anything to publish" check
            // below, because as of the broadcast-target selector a PC leg
            // can now be the *only* leg — a Leg-B-only precondition written
            // before Leg A existed. `capture.startCamera`/`startScreencast`
            // + `startMicrophone` above already ran unconditionally, and
            // WebRtcCameraOutput is just another MediaOutput on that same
            // mixer, exactly like an RTMP Stream is — there is no
            // structural reason Leg A can't stand alone.
            val requestedPeerConnectionId = (request["pcPeerConnectionId"] as? String)?.takeIf { it.isNotBlank() }
            if (requestedPeerConnectionId != null) {
                val (legAWidth, legAHeight) = if (usesProjection) width to height else portraitSize(width, height)
                attachWebRtcLeg(capture, requestedPeerConnectionId, legAWidth, legAHeight)
            }

            if (!PublisherAdmission.hasAnythingToStart(legSnapshots(), webRtcLeg != null)) {
                val message = if (requestedPeerConnectionId != null) {
                    // A PC leg was requested (Dart already confirmed the PC
                    // was connected before calling here) but attaching it
                    // still failed. attachWebRtcLeg is best-effort/silent by
                    // design when it's riding along with a live RTMP leg —
                    // but here it would have been the *only* leg, so
                    // silently publishing nothing is not acceptable; report
                    // it for real.
                    "Could not attach the PC video/audio track — the connection " +
                        "may have just dropped. Reconnect to the PC and try again."
                } else {
                    legs.firstOrNull()?.message ?: "No destination could be prepared."
                }
                fail(message)
                return@launch
            }

            for (leg in legs) {
                val session = leg.session ?: continue
                session.connect()
                    .onSuccess { leg.status = "live" }
                    .onFailure {
                        leg.status = "error"
                        leg.message = it.message ?: "Connection refused by the ingest server."
                        Log.e(TAG, "connect failed for ${leg.displayName}", it)
                    }
                emit(currentStatusMap())
            }

            // A PC-only session (legs empty by design) or a "both" session
            // where every RTMP destination happened to refuse the
            // connection can still be live via the already-attached PC leg.
            if (!PublisherAdmission.isAnythingLive(legSnapshots(), webRtcLeg != null)) {
                fail(legs.firstOrNull { it.message != null }?.message ?: "No leg connected.")
                return@launch
            }

            startStatsLoop()
            emit(currentStatusMap())
        }
    }

    /**
     * See CameraEncodeSession.portraitSize's doc comment — same swap,
     * duplicated rather than shared because it's a one-line pure function
     * and the two classes shouldn't otherwise couple to each other's
     * internals. Idempotent, so safe to apply to a value that might already
     * be portrait.
     */
    private fun portraitSize(width: Int, height: Int): Pair<Int, Int> =
        minOf(width, height) to maxOf(width, height)

    private fun buildLeg(
        map: Map<*, *>,
        width: Int,
        height: Int,
        fps: Int,
        codec: String,
        sampleRate: Int,
        channelCount: Int,
        audioBitrateKbps: Int,
    ): Leg {
        val destinationId = map["destinationId"] as? String ?: ""
        val displayName = map["displayName"] as? String ?: destinationId
        val url = map["url"] as? String ?: ""
        val streamKey = map["streamKey"] as? String ?: ""
        // width/height (global default or a per-destination VideoOverrides
        // resolution) always arrive landscape-style (e.g. 1920x1080) — but
        // in camera mode the mixer's canvas is portrait (see
        // CameraEncodeSession.startCamera's note), so the encoder must be
        // configured to match or it resizes a portrait frame into a
        // landscape one, distorting exactly like the preview did. Left
        // alone for screencast, whose canvas this pass doesn't touch.
        val rawLegWidth = (map["width"] as? Int) ?: width
        val rawLegHeight = (map["height"] as? Int) ?: height
        val (legWidth, legHeight) =
            if (usesProjection) rawLegWidth to rawLegHeight else portraitSize(rawLegWidth, rawLegHeight)
        val legFps = (map["fps"] as? Int) ?: fps
        val legBitrateKbps = (map["bitrateKbps"] as? Int) ?: DEFAULT_BITRATE_KBPS

        val scheme = Uri.parse(url).scheme?.lowercase()
        if (scheme == "srt") {
            // HaishinKit.kt has no SRT module (verified 2026-08-23); only
            // HaishinKit.swift does. Reported per-leg so the rest of a
            // multistream still goes out.
            return Leg(
                destinationId, displayName, legBitrateKbps, null, "error",
                "SRT is not supported on Android yet — use RTMP/RTMPS for $displayName.",
            )
        }
        if (scheme != "rtmp" && scheme != "rtmps") {
            return Leg(
                destinationId, displayName, legBitrateKbps, null, "error",
                "Unsupported ingest protocol \"$scheme\" for $displayName.",
            )
        }

        return try {
            val uri = Uri.parse(joinUrl(url, streamKey))
            val streamSession = StreamSession.Builder(applicationContext, uri)
                .setMode(StreamSession.Mode.PUBLISH)
                .build()

            streamSession.stream.videoSetting.apply {
                this.width = legWidth
                this.height = legHeight
                this.frameRate = legFps
                this.bitRate = legBitrateKbps * 1000
                profileLevelFor(codec)?.let {
                    try {
                        this.profileLevel = it
                    } catch (e: IllegalArgumentException) {
                        // The device has no encoder for the chosen codec —
                        // leave HaishinKit's H.264 default in place rather
                        // than failing the whole leg.
                        Log.w(TAG, "codec $codec unavailable, keeping default", e)
                    }
                }
            }
            streamSession.stream.audioSetting.apply {
                this.sampleRate = sampleRate
                this.channelCount = channelCount
                this.bitRate = audioBitrateKbps * 1000
            }

            // A Stream *is* a MediaOutput, so registering it on the mixer is
            // what makes a second destination a second consumer of the one
            // capture session rather than a second capture.
            session().registerOutput(streamSession.stream)
            Leg(destinationId, displayName, legBitrateKbps, streamSession, "connecting")
        } catch (e: Exception) {
            Log.e(TAG, "could not build leg for $displayName", e)
            Leg(destinationId, displayName, legBitrateKbps, null, "error", e.message ?: "Invalid ingest URL.")
        }
    }

    fun stop() {
        if (!isPublishing) return
        isPublishing = false
        statsJob?.cancel()
        statsJob = null

        val closing = legs.toList()
        legs.clear()
        legFps.clear()
        quality = null
        measuredKbps = null
        scope.launch {
            closeLegs(closing)
            detachWebRtcLeg()
            captureSession?.stopMicrophone()
            if (usesProjection) {
                // The projection belongs to ScreenCaptureForegroundService;
                // drop our consumer of it and go back to the camera preview
                // the UI expects when it returns to camera mode.
                captureSession?.let { it.release() }
                captureSession = null
            }
            usesProjection = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            emit(currentStatusMap())
        }
    }

    fun setMuted(muted: Boolean) {
        isMuted = muted
        captureSession?.setMuted(muted)
        // Leg A's audio is a separate capture from the mixer's (see
        // attachWebRtcAudio) — muting one does not mute the other, so both
        // need the call.
        webRtcAudioTrack?.setEnabled(!muted)
    }

    /**
     * Aborts a start that could not reach "live". The legs themselves are kept
     * so [currentStatusMap] can still report which destination failed and why
     * (the next [start] discards them) — but their sessions must be closed all
     * the same: a multistream can have one leg already connected when a later
     * one fails, and that socket would otherwise stay open with no way to stop
     * it, since [stop] returns early once publishing is over.
     */
    private fun fail(message: String) {
        lastError = message
        isPublishing = false
        statsJob?.cancel()
        statsJob = null
        val closing = legs.toList()
        scope.launch {
            closeLegs(closing)
            detachWebRtcLeg()
            captureSession?.stopMicrophone()
            usesProjection = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            emit(currentStatusMap())
        }
    }

    /**
     * Attaches the PC leg's video track — see [WebRtcCameraOutput]'s doc
     * comment for the whole design. Best-effort and silent on failure (just
     * logged): a paired PC that can't receive video yet must never take down
     * the RTMP legs that *are* working, so every failure path here falls
     * through to "no Leg A this session" rather than calling [fail].
     *
     * This function itself never fails loudly — but its caller in [start]
     * may still turn a failed attach into a real, reported [fail] if this
     * was the *only* leg requested (a PC-only `BroadcastTarget.toPc`
     * session), since "no Leg A this session" would otherwise mean
     * publishing nothing at all with no indication why.
     */
    private fun attachWebRtcLeg(capture: CameraEncodeSession, peerConnectionId: String, width: Int, height: Int) {
        if (webRtcLeg != null) return
        enableWebRtcLoggingOnDebugBuilds()
        val plugin = FlutterWebRTCPlugin.sharedSingleton
        val factory = plugin?.peerConnectionFactory
        if (plugin == null || factory == null) {
            Log.w(TAG, "Leg A: FlutterWebRTCPlugin/PeerConnectionFactory not ready, skipping")
            return
        }
        val output = try {
            WebRtcCameraOutput(applicationContext, factory, width, height)
        } catch (e: Exception) {
            Log.e(TAG, "Leg A: could not build the WebRTC video output", e)
            return
        }
        if (!plugin.attachExternalTrack(peerConnectionId, output.track)) {
            Log.w(TAG, "Leg A: attachExternalTrack failed (stale/closed peer connection $peerConnectionId?)")
            output.release()
            return
        }
        capture.registerOutput(output)
        webRtcLeg = output
        webRtcPeerConnectionId = peerConnectionId

        attachWebRtcAudio(plugin, factory, peerConnectionId)
    }

    /**
     * Leg A's audio, as a **second, independent microphone capture** rather
     * than fed from the mixer every RTMP leg (and Leg A's own video) shares.
     *
     * This is the mirror image of the video design, deliberately: WebRTC's
     * own `AudioDeviceModule` interface requires a real native pointer with
     * no supported way to substitute a different audio source, and the class
     * that actually owns the mic (`WebRtcAudioRecord`) is package-private and
     * drives native code directly — there is no safe hook to feed it
     * HaishinKit's captured PCM instead. Unlike the camera, though, Android
     * does not treat the microphone as hardware-exclusive, so a second
     * concurrent `AudioRecord` session (this one, owned entirely by
     * flutter_webrtc's already-configured `PeerConnectionFactory`) is the
     * supported, un-hacky way to get audio onto this leg. Cost: this
     * capture's mute state is independent of the mixer's (see [setMuted]),
     * and it applies its own (not HaishinKit's) AEC/NS.
     */
    private fun attachWebRtcAudio(plugin: FlutterWebRTCPlugin, factory: PeerConnectionFactory, peerConnectionId: String) {
        if (webRtcAudioTrack != null) return
        val source = try {
            factory.createAudioSource(MediaConstraints())
        } catch (e: Exception) {
            Log.e(TAG, "Leg A: could not create the audio source", e)
            return
        }
        val track = factory.createAudioTrack("phoneCamLegAAudio", source)
        if (!plugin.attachExternalTrack(peerConnectionId, track)) {
            Log.w(TAG, "Leg A: attachExternalTrack failed for audio")
            track.dispose()
            source.dispose()
            return
        }
        track.setEnabled(!isMuted)
        webRtcAudioSource = source
        webRtcAudioTrack = track
    }

    /**
     * Routes libwebrtc's own native logging into logcat, on debuggable
     * builds only.
     *
     * Without this, everything libwebrtc decides about Leg A — which video
     * encoder it picked, whether that encoder initialised, whether it is
     * producing and sending RTP — happens entirely inside the native
     * library and is invisible from both sides of the connection. The app's
     * own logs can only ever show that a track was created and handed over,
     * which stays true no matter what libwebrtc then does with it.
     *
     * Gated on FLAG_DEBUGGABLE and attached lazily the first time a PC leg
     * is set up rather than at process start, and at LS_WARNING rather than
     * LS_INFO: this device's PowerVR driver already floods logcat badly
     * enough to hide real messages (see `scripts/filtered_logcat.ps1`), and
     * libwebrtc at LS_INFO adds a per-frame stream of its own. Warnings
     * still carry the things worth catching — encoder init failures,
     * codec negotiation problems, send errors — without the flood. Raise it
     * to LS_INFO temporarily when a specific investigation needs it.
     */
    private fun enableWebRtcLoggingOnDebugBuilds() {
        if (webRtcLoggingEnabled) return
        webRtcLoggingEnabled = true
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
        try {
            Logging.enableLogToDebugOutput(Logging.Severity.LS_WARNING)
            Log.i(TAG, "Leg A: libwebrtc native logging enabled (debug build)")
        } catch (e: Throwable) {
            Log.w(TAG, "Leg A: could not enable libwebrtc logging", e)
        }
    }

    private fun detachWebRtcLeg() {
        val output = webRtcLeg
        val peerConnectionId = webRtcPeerConnectionId
        webRtcLeg = null
        webRtcPeerConnectionId = null
        if (output != null) {
            captureSession?.unregisterOutput(output)
            if (peerConnectionId != null) {
                FlutterWebRTCPlugin.sharedSingleton?.detachExternalTrack(peerConnectionId, output.track)
            }
            output.release()
        }

        val audioTrack = webRtcAudioTrack
        webRtcAudioTrack = null
        val audioSource = webRtcAudioSource
        webRtcAudioSource = null
        if (audioTrack != null) {
            if (peerConnectionId != null) {
                FlutterWebRTCPlugin.sharedSingleton?.detachExternalTrack(peerConnectionId, audioTrack)
            }
            audioTrack.dispose()
        }
        audioSource?.dispose()
    }

    private suspend fun closeLegs(closing: List<Leg>) {
        for (leg in closing) {
            val session = leg.session ?: continue
            captureSession?.unregisterOutput(session.stream)
            // close() reports failure for a session that never connected;
            // that is the normal case here, not something to act on. The leg's
            // status is deliberately left alone so a failure reason survives
            // into the status map.
            session.close()
        }
    }

    /**
     * Polls each leg for the stats the status pill shows. HaishinKit reports
     * a measured frame rate ([RtmpStream.currentFPS]) but not a measured
     * output bitrate, so the bitrate reported here is the configured target —
     * measuring the real one is part of Phase 6's adaptive-bitrate work,
     * which needs socket-level backpressure anyway.
     */
    private fun startStatsLoop() {
        statsJob?.cancel()
        statsJob = scope.launch {
            while (isActive && isPublishing) {
                sampleThroughput()
                updateLegStates()
                retryDisconnectedLegs()
                applyQualityDecision()
                emit(currentStatusMap())
                delay(STATS_INTERVAL_MS)
            }
        }
    }

    private fun beginMeasuring() {
        txBytesAtStart = TrafficStats.getUidTxBytes(Process.myUid())
        lastTxBytes = txBytesAtStart
        lastSampleAtMs = SystemClock.elapsedRealtime()
        measuredKbps = null
        bytesSent = 0
    }

    /**
     * Measures real outgoing throughput from the platform's per-UID transmit
     * counter. This counts everything the process sends, not just the RTMP
     * legs, but while publishing the legs dominate by orders of magnitude —
     * and it is the only measurement available, since HaishinKit's own
     * per-connection counters are module-internal.
     */
    private fun sampleThroughput() {
        if (txBytesAtStart == UNSUPPORTED_TX) return

        val now = SystemClock.elapsedRealtime()
        val total = TrafficStats.getUidTxBytes(Process.myUid())
        if (total == UNSUPPORTED_TX) return

        val elapsedMs = now - lastSampleAtMs
        val deltaBytes = total - lastTxBytes
        lastTxBytes = total
        lastSampleAtMs = now
        bytesSent = (total - txBytesAtStart).coerceAtLeast(0)

        if (elapsedMs <= 0 || deltaBytes < 0) return
        measuredKbps = ((deltaBytes * 8.0) / elapsedMs).toInt()
    }

    private fun updateLegStates() {
        for (leg in legs) {
            val session = leg.session ?: continue
            if (leg.status == "live" && !session.isConnected) {
                leg.status = "reconnecting"
                leg.retries = 0
                leg.nextRetryAtMs = SystemClock.elapsedRealtime() + FIRST_RETRY_DELAY_MS
            } else if (leg.status == "reconnecting" && session.isConnected) {
                leg.status = "live"
                leg.retries = 0
                leg.message = null
            }
            (session.stream as? RtmpStream)?.let { legFps[leg.destinationId] = it.currentFPS }
        }
    }

    /**
     * Reconnects dropped legs on an exponential backoff. Backing off matters
     * more than retrying fast: an ingest that just refused a connection is
     * usually still refusing a second later, and hammering it burns battery
     * and mobile data for nothing.
     */
    private suspend fun retryDisconnectedLegs() {
        val now = SystemClock.elapsedRealtime()
        for (leg in legs) {
            val session = leg.session ?: continue
            if (leg.status != "reconnecting" || now < leg.nextRetryAtMs) continue

            if (leg.retries >= MAX_RETRIES) {
                leg.status = "error"
                leg.message = "Lost the connection to ${leg.displayName} and could not get it back."
                continue
            }

            leg.retries++
            session.connect()
                .onSuccess {
                    leg.status = "live"
                    leg.retries = 0
                    leg.message = null
                }
                .onFailure {
                    val backoff = (FIRST_RETRY_DELAY_MS shl (leg.retries - 1))
                        .coerceAtMost(MAX_RETRY_DELAY_MS)
                    leg.nextRetryAtMs = SystemClock.elapsedRealtime() + backoff
                    leg.message = it.message
                }
        }
    }

    /**
     * Feeds the latest throughput sample to the quality controller and, when
     * it asks for a change, reconfigures every leg's encoder. HaishinKit
     * applies both live: bitrate through `MediaCodec.PARAMETER_KEY_VIDEO_BITRATE`
     * (guarded by its own FEATURE_BITRATE_CHANGE flag, on by default) and
     * frame rate through the pixel transform.
     */
    private fun applyQualityDecision() {
        val controller = quality ?: return
        val measured = measuredKbps ?: return
        if (legs.none { it.status == "live" }) return
        if (!controller.onSample(measured)) return

        applyToEncoders(controller)
        Log.d(
            TAG,
            "adaptive: measured=${measured}kbps scale=${controller.effectiveScale} " +
                "fps=${controller.effectiveFrameRate}",
        )
    }

    private fun applyToEncoders(controller: NetworkQualityController) {
        for (leg in legs) {
            val stream = leg.session?.stream ?: continue
            leg.currentBitrateKbps = (leg.bitrateKbps * controller.effectiveScale).toInt()
            try {
                stream.videoSetting.bitRate = leg.currentBitrateKbps * 1000
                stream.videoSetting.frameRate = controller.effectiveFrameRate
            } catch (e: Exception) {
                Log.w(TAG, "could not apply quality to ${leg.displayName}", e)
            }
        }
    }

    /**
     * Caps quality on behalf of the battery/thermal guards (PLAN.md Phase 7).
     * Applied even when adaptive bitrate is switched off: the user turning off
     * *network* adaptation is not consent to keep cooking the phone, and the
     * guards have their own settings for that.
     */
    fun setQualityCeiling(scale: Double, frameRateCap: Int) {
        if (!isPublishing) {
            pendingCeiling = scale to frameRateCap
            return
        }
        val controller = quality ?: run {
            pendingCeiling = scale to frameRateCap
            guardOnlyController()
        }
        if (controller.setCeiling(scale, frameRateCap)) {
            applyToEncoders(controller)
            emit(currentStatusMap())
        }
    }

    /**
     * A controller used purely to carry a guard ceiling when the user has
     * turned network adaptation off — it is never fed samples, so it only ever
     * reports what the guards asked for.
     */
    private fun guardOnlyController(): NetworkQualityController {
        val created = NetworkQualityController(baseBitrateKbps, baseFrameRate)
        quality = created
        return created
    }

    /** [legs] reduced to what [PublisherAdmission] needs to know about each. */
    private fun legSnapshots(): List<PublisherAdmission.LegSnapshot> =
        legs.map { PublisherAdmission.LegSnapshot(hasSession = it.session != null, status = it.status) }

    fun currentStatusMap(): Map<String, Any?> {
        val destinations = legs.map { leg ->
            mapOf(
                "destinationId" to leg.destinationId,
                "status" to leg.status,
                "targetBitrateKbps" to leg.currentBitrateKbps,
                "message" to leg.message,
            )
        }

        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = legSnapshots(),
            webRtcLegAttached = webRtcLeg != null,
            isPublishing = isPublishing,
            hasUnclearedError = lastError != null,
        )

        return mapOf(
            "status" to status,
            "destinations" to destinations,
            "bitrateKbps" to measuredKbps,
            "targetBitrateKbps" to
                legs.filter { it.status == "live" }.sumOf { it.currentBitrateKbps }.takeIf { it > 0 },
            "bytesSent" to bytesSent.takeIf { isPublishing || it > 0 },
            "fps" to legFps.values.maxOrNull(),
            "uptimeSeconds" to
                if (isPublishing) ((SystemClock.elapsedRealtime() - startedAtMs) / 1000).toInt() else null,
            "message" to lastError,
        )
    }

    /** Preview/capture state, reported on its own channel. */
    fun currentCameraStatusMap(): Map<String, Any?> {
        val capture = captureSession
        return mapOf(
            "status" to if (capture?.isRunning == true) "running" else "idle",
            "textureId" to capture?.previewTextureId,
            "width" to capture?.previewWidth,
            "height" to capture?.previewHeight,
            "lensFacingFront" to (capture?.lensFacingFront ?: false),
            "hasMultipleCameras" to hasMultipleCameras(),
        )
    }

    private fun emit(map: Map<String, Any?>) {
        onEvent?.invoke(map)
    }

    private fun emitCamera() {
        onCameraEvent?.invoke(currentCameraStatusMap())
    }

    private fun promoteToForeground() {
        val channelId = "publisher"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Live stream",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Streaming")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // The declared type has to match what is actually being captured:
            // a MediaProjection-backed stream is not a "camera" foreground
            // service, and Android 14+ rejects the mismatch outright.
            val type = if (usesProjection) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        statsJob?.cancel()
        detachWebRtcLeg()
        val capture = captureSession
        captureSession = null
        scope.launch { capture?.release() }
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_ID = 2
        private const val STATS_INTERVAL_MS = 1000L
        private const val DEFAULT_WIDTH = 1920
        private const val DEFAULT_HEIGHT = 1080
        private const val DEFAULT_BITRATE_KBPS = 4500
        private const val UNSUPPORTED_TX = -1L
        private const val FIRST_RETRY_DELAY_MS = 1000L
        private const val MAX_RETRY_DELAY_MS = 30_000L
        private const val MAX_RETRIES = 10
        private val TAG = PublisherForegroundService::class.java.simpleName

        init {
            StreamSession.Builder.registerFactory(RtmpStreamSessionFactory)
        }

        /**
         * RTMP ingests take the stream key as the final path component of the
         * URL (`rtmp://host/app/<key>`) — the same "server URL + stream key"
         * split every broadcaster UI uses.
         */
        fun joinUrl(url: String, streamKey: String): String {
            if (streamKey.isEmpty()) return url
            return if (url.endsWith("/")) "$url$streamKey" else "$url/$streamKey"
        }

        fun profileLevelFor(codec: String): VideoCodecProfileLevel? = when (codec) {
            "hevc" -> VideoCodecProfileLevel.HEVC_MAIN_4_1
            "av1" -> VideoCodecProfileLevel.AV1_MAIN8_4_1
            "h264" -> VideoCodecProfileLevel.H264_HIGH_4_1
            else -> null
        }

        /**
         * Video codecs this device has a hardware encoder for. Queried from
         * `MediaCodecList` rather than a hardcoded list because AV1 encode in
         * particular exists on only a few SoCs (PLAN.md §1.5), and answering
         * "supported" for one that isn't would fail at encoder-configure time
         * with nothing useful to show the user.
         */
        fun supportedCodecs(): List<String> {
            val mimes = mapOf(
                "h264" to MediaFormat.MIMETYPE_VIDEO_AVC,
                "hevc" to MediaFormat.MIMETYPE_VIDEO_HEVC,
                "av1" to MediaFormat.MIMETYPE_VIDEO_AV1,
            )
            val available = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder }
                .flatMap { it.supportedTypes.toList() }
                .map { it.lowercase() }
                .toSet()
            val supported = mimes.filterValues { available.contains(it.lowercase()) }.keys.toList()
            // Every Android device that can encode at all has AVC; if the
            // query somehow comes back empty, claiming nothing is worse than
            // claiming the universal baseline.
            return supported.ifEmpty { listOf("h264") }
        }
    }
}
