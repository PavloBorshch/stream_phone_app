package com.example.stream_phone_cam

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers the leg-admission/status decision the broadcast-target selector's
 * "To PC" option now depends on (2026-08-28) — same "pure decision, JVM
 * tested" treatment PLAN.md §3.4 already applies to
 * [NetworkQualityControllerTest].
 */
class PublisherAdmissionTest {

    private fun leg(hasSession: Boolean, status: String) =
        PublisherAdmission.LegSnapshot(hasSession, status)

    private val liveLeg = leg(hasSession = true, status = "live")
    private val connectingLeg = leg(hasSession = true, status = "connecting")
    private val reconnectingLeg = leg(hasSession = true, status = "reconnecting")
    private val erroredLeg = leg(hasSession = false, status = "error")

    // --- hasAnythingToStart --------------------------------------------

    @Test
    fun `zero RTMP legs with the PC leg attached is worth starting`() {
        assertTrue(PublisherAdmission.hasAnythingToStart(emptyList(), webRtcLegAttached = true))
    }

    @Test
    fun `zero RTMP legs with no PC leg attached is not worth starting`() {
        assertFalse(PublisherAdmission.hasAnythingToStart(emptyList(), webRtcLegAttached = false))
    }

    @Test
    fun `an RTMP leg with a built session is worth starting even before connect() runs`() {
        assertTrue(
            PublisherAdmission.hasAnythingToStart(listOf(connectingLeg), webRtcLegAttached = false),
        )
    }

    @Test
    fun `RTMP legs that all failed to build and no PC leg is not worth starting`() {
        assertFalse(
            PublisherAdmission.hasAnythingToStart(listOf(erroredLeg), webRtcLegAttached = false),
        )
    }

    // --- isAnythingLive ---------------------------------------------------

    @Test
    fun `zero RTMP legs with the PC leg attached counts as live`() {
        assertTrue(PublisherAdmission.isAnythingLive(emptyList(), webRtcLegAttached = true))
    }

    @Test
    fun `zero RTMP legs with the PC leg attach failed does not count as live`() {
        assertFalse(PublisherAdmission.isAnythingLive(emptyList(), webRtcLegAttached = false))
    }

    @Test
    fun `an actually-live RTMP leg counts regardless of the PC leg`() {
        assertTrue(PublisherAdmission.isAnythingLive(listOf(liveLeg), webRtcLegAttached = false))
    }

    @Test
    fun `RTMP legs that only reached connecting or error do not count as live on their own`() {
        assertFalse(
            PublisherAdmission.isAnythingLive(
                listOf(connectingLeg, erroredLeg),
                webRtcLegAttached = false,
            ),
        )
    }

    // --- aggregateStatus ----------------------------------------------

    @Test
    fun `a PC-only session with zero RTMP legs reports live, not stuck connecting`() {
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = emptyList(),
            webRtcLegAttached = true,
            isPublishing = true,
            hasUnclearedError = false,
        )
        assertEquals("live", status)
    }

    @Test
    fun `every RTMP leg erroring mid-session with the PC leg attached stays live`() {
        // A "both" session where every RTMP destination has exhausted its
        // retries and gone permanently to "error" — the PC leg is still up,
        // so this must not fall through to "connecting" forever.
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = listOf(erroredLeg, erroredLeg),
            webRtcLegAttached = true,
            isPublishing = true,
            hasUnclearedError = false,
        )
        assertEquals("live", status)
    }

    @Test
    fun `RTMP legs with no PC leg behave exactly as before — a live leg wins`() {
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = listOf(liveLeg, reconnectingLeg),
            webRtcLegAttached = false,
            isPublishing = true,
            hasUnclearedError = false,
        )
        assertEquals("live", status)
    }

    @Test
    fun `RTMP legs with no PC leg behave exactly as before — reconnecting shows when none are live`() {
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = listOf(reconnectingLeg, erroredLeg),
            webRtcLegAttached = false,
            isPublishing = true,
            hasUnclearedError = false,
        )
        assertEquals("reconnecting", status)
    }

    @Test
    fun `RTMP legs with no PC leg behave exactly as before — connecting before anything settles`() {
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = listOf(connectingLeg),
            webRtcLegAttached = false,
            isPublishing = true,
            hasUnclearedError = false,
        )
        assertEquals("connecting", status)
    }

    @Test
    fun `idle when nothing is publishing and no RTMP legs remain, regardless of error`() {
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = emptyList(),
            webRtcLegAttached = false,
            isPublishing = false,
            hasUnclearedError = false,
        )
        assertEquals("idle", status)
    }

    @Test
    fun `an uncleared error while not publishing reports error, taking priority over idle`() {
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = emptyList(),
            webRtcLegAttached = false,
            isPublishing = false,
            hasUnclearedError = true,
        )
        assertEquals("error", status)
    }

    @Test
    fun `stopped when publishing has ended cleanly with legs still on record`() {
        val status = PublisherAdmission.aggregateStatus(
            rtmpLegs = listOf(erroredLeg),
            webRtcLegAttached = false,
            isPublishing = false,
            hasUnclearedError = false,
        )
        assertEquals("stopped", status)
    }
}
