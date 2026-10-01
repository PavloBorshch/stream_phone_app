package com.example.stream_phone_cam

/**
 * Pure, Android/HaishinKit-free admission and status decision for a
 * publishing session's legs — the JVM-testable counterpart to
 * [NetworkQualityController] (PLAN.md §3.4). That class is deliberately free
 * of framework types so its tuning can be unit tested on the JVM; this one
 * gets the same treatment because it now decides whether the broadcast-target
 * selector's "To PC" option starts a session at all (2026-08-28) — that's a
 * pure decision with no framework dependency, same shape as the control law,
 * and it earns a real test rather than a comment.
 *
 * [PublisherForegroundService] owns every side effect — building legs,
 * calling `connect()`, attaching the WebRTC leg via `attachWebRtcLeg`,
 * promoting to the foreground, and so on. This object only answers the
 * questions that used to be inlined `legs.none { ... }` checks and an inlined
 * `when` in `currentStatusMap()`: given what happened, is there anything
 * worth starting, is anything actually live, and what should the aggregate
 * status say.
 */
object PublisherAdmission {

    /**
     * What this decision needs to know about one RTMP/RTMPS leg. [status] is
     * the same string `PublisherForegroundService.Leg` already carries
     * ("connecting"/"live"/"reconnecting"/"error") — kept as a plain string
     * rather than a new enum so this stays a narrow extraction of the
     * existing decision, not a reshaping of the leg model around it.
     */
    data class LegSnapshot(val hasSession: Boolean, val status: String)

    /**
     * Before any RTMP `connect()` calls: is there anything here worth
     * attempting at all? `false` means the caller should fail the whole
     * start attempt rather than call `connect()` on zero usable legs.
     * Mirrors `PublisherForegroundService.start`'s first "nothing to
     * publish" guard.
     */
    fun hasAnythingToStart(rtmpLegs: List<LegSnapshot>, webRtcLegAttached: Boolean): Boolean {
        return rtmpLegs.any { it.hasSession } || webRtcLegAttached
    }

    /**
     * After every RTMP leg's `connect()` has been attempted: did anything
     * actually come up live? Mirrors the service's second "nothing
     * connected" guard — this is what lets a PC-only session ([rtmpLegs]
     * empty by design) or a "both" session where every RTMP leg refused the
     * connection still count as a successful start.
     */
    fun isAnythingLive(rtmpLegs: List<LegSnapshot>, webRtcLegAttached: Boolean): Boolean {
        return rtmpLegs.any { it.status == "live" } || webRtcLegAttached
    }

    /**
     * The aggregate status `currentStatusMap()` reports to Dart. Mirrors
     * that function's `when` exactly, so every branch — including "an
     * attached PC leg alone reads as live even with zero/all-failed RTMP
     * legs" — is independently testable rather than only reachable through
     * the full Android `Service`.
     */
    fun aggregateStatus(
        rtmpLegs: List<LegSnapshot>,
        webRtcLegAttached: Boolean,
        isPublishing: Boolean,
        hasUnclearedError: Boolean,
    ): String = when {
        hasUnclearedError && !isPublishing -> "error"
        !isPublishing && rtmpLegs.isEmpty() -> "idle"
        rtmpLegs.any { it.status == "live" } -> "live"
        // Covers both a PC-only session (rtmpLegs empty by design) and a
        // "both" session where every RTMP leg has failed/errored out but the
        // PC leg is still attached and delivering — without this, either
        // case would fall through to "connecting" forever, since every
        // other branch only looks at rtmpLegs.
        isPublishing && webRtcLegAttached -> "live"
        rtmpLegs.any { it.status == "reconnecting" } -> "reconnecting"
        isPublishing -> "connecting"
        else -> "stopped"
    }
}
