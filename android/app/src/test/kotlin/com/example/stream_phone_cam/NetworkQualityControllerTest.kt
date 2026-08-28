package com.example.stream_phone_cam

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers the tuning law PLAN.md §3.4 flags as the risky part of adaptive
 * streaming — in particular that it settles instead of oscillating.
 */
class NetworkQualityControllerTest {
    private fun controller(bitrate: Int = 4500, fps: Int = 60) =
        NetworkQualityController(bitrate, fps)

    /** Feeds [count] samples at [kbps], returning how many caused a change. */
    private fun feed(controller: NetworkQualityController, kbps: Int, count: Int): Int {
        var changes = 0
        repeat(count) { if (controller.onSample(kbps)) changes++ }
        return changes
    }

    @Test
    fun `starts undegraded at the configured quality`() {
        val controller = controller()
        assertEquals(4500, controller.targetBitrateKbps)
        assertEquals(60, controller.frameRate)
        assertFalse(controller.isDegraded)
    }

    @Test
    fun `a healthy link is left alone`() {
        val controller = controller()
        assertEquals(0, feed(controller, 4500, 60))
        assertFalse(controller.isDegraded)
    }

    @Test
    fun `throughput between the thresholds does not drift into a change`() {
        val controller = controller()
        // 80% of target: not good enough to recover from, not bad enough to
        // act on. A control law with a single threshold would oscillate here.
        assertEquals(0, feed(controller, 3600, 120))
        assertFalse(controller.isDegraded)
    }

    @Test
    fun `a single bad sample is not enough to drop quality`() {
        val controller = controller()
        assertFalse(controller.onSample(500))
        assertFalse(controller.isDegraded)
    }

    @Test
    fun `sustained shortfall steps the bitrate down`() {
        val controller = controller()
        repeat(NetworkQualityController.SAMPLES_BEFORE_DOWN) { controller.onSample(500) }
        assertEquals(0.8, controller.scale, 1e-9)
        assertEquals(60, controller.frameRate)
        assertTrue(controller.isDegraded)
    }

    @Test
    fun `zero throughput is ignored rather than treated as a stall`() {
        val controller = controller()
        assertEquals(0, feed(controller, 0, 20))
        assertFalse(controller.isDegraded)
    }

    @Test
    fun `bitrate bottoms out before the frame rate is touched`() {
        val controller = controller()
        // A link delivering almost nothing, for a long time.
        feed(controller, 100, 400)
        assertEquals(NetworkQualityController.MIN_SCALE, controller.scale, 1e-9)
        assertEquals(24, controller.frameRate)
    }

    @Test
    fun `frame rate steps down the ladder, never below 24`() {
        assertEquals(30, NetworkQualityController.nextFrameRateDown(60))
        assertEquals(24, NetworkQualityController.nextFrameRateDown(30))
        assertEquals(24, NetworkQualityController.nextFrameRateDown(24))
    }

    @Test
    fun `frame rate recovery never exceeds the configured ceiling`() {
        assertEquals(30, NetworkQualityController.nextFrameRateUp(24, 60))
        assertEquals(60, NetworkQualityController.nextFrameRateUp(30, 60))
        // A stream configured for 30 must not "recover" to 60.
        assertEquals(30, NetworkQualityController.nextFrameRateUp(24, 30))
        assertEquals(30, NetworkQualityController.nextFrameRateUp(30, 30))
    }

    @Test
    fun `recovery restores frame rate before bitrate`() {
        val controller = controller()
        feed(controller, 100, 400)
        assertEquals(24, controller.frameRate)
        val degradedScale = controller.scale

        // A link that is now comfortably carrying the reduced target.
        feed(controller, 4500, NetworkQualityController.SAMPLES_BEFORE_UP +
            NetworkQualityController.COOLDOWN_SAMPLES + 1)

        assertEquals(30, controller.frameRate)
        assertEquals(degradedScale, controller.scale, 1e-9)
    }

    @Test
    fun `a good link eventually restores the configured quality exactly`() {
        val controller = controller()
        feed(controller, 500, 20)
        assertTrue(controller.isDegraded)

        feed(controller, 100000, 2000)

        assertEquals(1.0, controller.scale, 1e-9)
        assertEquals(60, controller.frameRate)
        assertFalse(controller.isDegraded)
        // Recovery must not overshoot the user's configured bitrate.
        assertEquals(4500, controller.targetBitrateKbps)
    }

    @Test
    fun `recovery is slower than degradation`() {
        val downController = controller()
        var samplesToDrop = 0
        while (!downController.isDegraded) {
            downController.onSample(100)
            samplesToDrop++
        }

        val upController = controller()
        upController.onSample(100)
        upController.onSample(100)
        upController.onSample(100)
        var samplesToRecover = 0
        while (upController.isDegraded && samplesToRecover < 1000) {
            upController.onSample(100000)
            samplesToRecover++
        }

        assertTrue(
            "recovery ($samplesToRecover) should take longer than degradation ($samplesToDrop)",
            samplesToRecover > samplesToDrop,
        )
    }

    @Test
    fun `a link pinned just under target settles instead of flapping`() {
        val controller = controller()
        // Throughput that tracks 60% of whatever is currently asked for: the
        // classic flapping setup, since every step down is followed by a
        // proportionally worse measurement.
        var changes = 0
        repeat(600) {
            val measured = (controller.targetBitrateKbps * 0.6).toInt()
            if (controller.onSample(measured)) changes++
        }

        // It must come to rest at the floor rather than churning forever.
        assertEquals(NetworkQualityController.MIN_SCALE, controller.scale, 1e-9)
        assertEquals(24, controller.frameRate)
        assertTrue("settled after $changes changes", changes < 20)
    }

    @Test
    fun `the cooldown prevents reacting to the effect of its own last change`() {
        val controller = controller()
        repeat(NetworkQualityController.SAMPLES_BEFORE_DOWN) { controller.onSample(100) }
        val scaleAfterFirstDrop = controller.scale

        // Immediately after a change, further bad samples are absorbed by the
        // cooldown instead of stacking a second drop straight away.
        repeat(NetworkQualityController.COOLDOWN_SAMPLES) {
            assertFalse(controller.onSample(100))
        }
        assertEquals(scaleAfterFirstDrop, controller.scale, 1e-9)
    }

    // --- guard ceiling (battery / thermal, PLAN.md Phase 7) ----------------

    @Test
    fun `a ceiling caps the applied quality without touching the network law`() {
        val controller = controller()

        assertTrue(controller.setCeiling(0.5, 30))

        assertEquals(2250, controller.targetBitrateKbps)
        assertEquals(30, controller.effectiveFrameRate)
        // The network law itself has decided nothing — the cap is external.
        assertEquals(1.0, controller.scale, 1e-9)
        assertEquals(60, controller.frameRate)
        assertFalse(controller.isDegraded)
        assertTrue(controller.isConstrained)
    }

    @Test
    fun `lifting the ceiling restores what the network law had decided`() {
        val controller = controller()
        // Network drops quality on its own...
        feed(controller, 500, 20)
        val networkScale = controller.scale
        assertTrue(networkScale < 1.0)

        // ...then a guard caps it further, then the guard is released.
        controller.setCeiling(0.25, 24)
        controller.clearCeiling()

        // The network's own decision survives; it does not snap back to full.
        assertEquals(networkScale, controller.effectiveScale, 1e-9)
        assertEquals(controller.frameRate, controller.effectiveFrameRate)
    }

    @Test
    fun `the tighter of network and ceiling wins`() {
        val controller = controller()
        feed(controller, 500, 20)
        val networkScale = controller.scale

        // A ceiling looser than the network's decision changes nothing.
        controller.setCeiling(1.0, 60)
        assertEquals(networkScale, controller.effectiveScale, 1e-9)

        // A tighter one takes over.
        controller.setCeiling(MIN_SCALE_FOR_TEST, 24)
        assertEquals(MIN_SCALE_FOR_TEST, controller.effectiveScale, 1e-9)
        assertEquals(24, controller.effectiveFrameRate)
    }

    @Test
    fun `setCeiling reports whether anything actually changed`() {
        val controller = controller()

        assertTrue(controller.setCeiling(0.5, 30))
        // Re-applying the same ceiling is not a change worth reconfiguring for.
        assertFalse(controller.setCeiling(0.5, 30))
        assertTrue(controller.clearCeiling())
    }

    @Test
    fun `a ceiling is clamped to the same floor as the network law`() {
        val controller = controller()

        controller.setCeiling(0.01, 24)

        assertEquals(NetworkQualityController.MIN_SCALE, controller.effectiveScale, 1e-9)
    }

    @Test
    fun `the network law measures against what is actually being sent`() {
        val controller = controller()
        controller.setCeiling(0.5, 60)

        // 2000 kbps against a 2250 capped target is healthy; against the
        // uncapped 4500 it would look like a shortfall and wrongly step down.
        assertEquals(0, feed(controller, 2000, 20))
        assertEquals(1.0, controller.scale, 1e-9)
    }

    private companion object {
        const val MIN_SCALE_FOR_TEST = NetworkQualityController.MIN_SCALE
    }
}
