package com.example.stream_phone_cam

/**
 * Decides how far to back off encoder quality when the uplink cannot carry the
 * configured bitrate (PLAN.md §3.4).
 *
 * Deliberately free of Android and HaishinKit types so the tuning — the part
 * §3.4 warns is a tuning problem rather than a coding one — can be unit
 * tested on the JVM. The caller feeds it a measured throughput once per
 * second and applies whatever [scale] and [frameRate] it reports.
 *
 * ### What is being measured, and why it isn't per-leg
 * HaishinKit keeps `RtmpStream.connection` `internal` to its own Gradle
 * module, so its per-connection byte counters are unreachable from this app.
 * The measurement is therefore the process-wide transmit counter
 * (`TrafficStats.getUidTxBytes`), which is accurate for the session as a whole
 * but cannot attribute throughput to one destination out of several. So the
 * same scale is applied to every leg rather than starving one in particular.
 *
 * ### Control law
 * Backing off is cheap and recovering is expensive (a step up that the network
 * cannot hold produces a visible stutter, then another step down), so the two
 * directions are deliberately asymmetric: drop after a few bad samples, and
 * only recover after a long clean run. A cooldown after every change stops the
 * loop reacting to its own last adjustment, which is what "flapping" is.
 */
class NetworkQualityController(
    private val baseBitrateKbps: Int,
    private val baseFrameRate: Int,
) {
    /**
     * Fraction of the configured bitrate the *network* law has settled on.
     * The value actually applied is [effectiveScale], which also respects the
     * ceiling below.
     */
    var scale: Double = 1.0
        private set

    /** Frame rate the network law has settled on, before [frameRateCeiling]. */
    var frameRate: Int = baseFrameRate
        private set

    /**
     * An externally imposed cap, used by the battery and thermal guards
     * (PLAN.md Phase 7). Kept separate from [scale] rather than folded into it
     * so the two concerns cannot fight: when the phone cools down or is
     * plugged in, lifting the ceiling restores whatever the network law had
     * independently decided, instead of having to rediscover it.
     */
    var ceilingScale: Double = 1.0
        private set

    var frameRateCeiling: Int = Int.MAX_VALUE
        private set

    val effectiveScale: Double get() = minOf(scale, ceilingScale)

    val effectiveFrameRate: Int get() = minOf(frameRate, frameRateCeiling)

    val targetBitrateKbps: Int get() = (baseBitrateKbps * effectiveScale).toInt()

    val isDegraded: Boolean get() = scale < 1.0 || frameRate < baseFrameRate

    /** True when anything — network or ceiling — is holding quality down. */
    val isConstrained: Boolean
        get() = isDegraded || effectiveScale < 1.0 || effectiveFrameRate < baseFrameRate

    /**
     * Applies a guard ceiling. Returns true when the applied quality changed,
     * so the caller knows to reconfigure the encoders.
     */
    fun setCeiling(scale: Double, frameRateCap: Int): Boolean {
        val previousScale = effectiveScale
        val previousFrameRate = effectiveFrameRate
        ceilingScale = scale.coerceIn(MIN_SCALE, 1.0)
        frameRateCeiling = if (frameRateCap <= 0) Int.MAX_VALUE else frameRateCap
        return effectiveScale != previousScale || effectiveFrameRate != previousFrameRate
    }

    fun clearCeiling(): Boolean = setCeiling(1.0, Int.MAX_VALUE)

    private var shortfalls = 0
    private var healthy = 0
    private var cooldown = 0

    /**
     * Feeds one throughput sample, in kbps. Returns true when [scale] or
     * [frameRate] changed and the caller should reconfigure the encoders.
     *
     * A sample of zero is ignored rather than treated as a total stall: the
     * first tick of a session, and any tick where the counter has not advanced
     * yet, legitimately reads zero, and reacting to that would step the
     * quality down before a single frame had a chance to go out.
     */
    fun onSample(measuredKbps: Int): Boolean {
        if (measuredKbps <= 0) return false
        if (cooldown > 0) {
            cooldown--
            return false
        }

        val target = targetBitrateKbps
        if (target <= 0) return false

        val ratio = measuredKbps.toDouble() / target

        if (ratio < DOWN_RATIO) {
            healthy = 0
            shortfalls++
            if (shortfalls >= SAMPLES_BEFORE_DOWN) return stepDown()
            return false
        }

        if (ratio >= UP_RATIO) {
            shortfalls = 0
            healthy++
            if (healthy >= SAMPLES_BEFORE_UP && isDegraded) return stepUp()
            return false
        }

        // In between the two thresholds the link is keeping up well enough to
        // leave alone: neither counter advances, so a stream hovering here
        // never drifts into a change on its own.
        shortfalls = 0
        healthy = 0
        return false
    }

    /** Bitrate gives way first; frame rate only once bitrate has bottomed out. */
    private fun stepDown(): Boolean {
        val changed = if (scale > MIN_SCALE) {
            scale = maxOf(MIN_SCALE, scale - DOWN_STEP)
            true
        } else {
            val next = nextFrameRateDown(frameRate)
            if (next != frameRate) {
                frameRate = next
                true
            } else {
                false
            }
        }
        if (changed) afterChange()
        return changed
    }

    /** Recovered in the reverse order, so motion smoothness returns first. */
    private fun stepUp(): Boolean {
        val changed = if (frameRate < baseFrameRate) {
            frameRate = nextFrameRateUp(frameRate, baseFrameRate)
            true
        } else if (scale < 1.0) {
            scale = minOf(1.0, scale + UP_STEP)
            true
        } else {
            false
        }
        if (changed) afterChange()
        return changed
    }

    private fun afterChange() {
        shortfalls = 0
        healthy = 0
        cooldown = COOLDOWN_SAMPLES
    }

    companion object {
        /** Below this fraction of target, the link is not carrying the stream. */
        const val DOWN_RATIO = 0.7

        /** At or above this, there is headroom to consider recovering. */
        const val UP_RATIO = 0.9

        const val SAMPLES_BEFORE_DOWN = 3
        const val SAMPLES_BEFORE_UP = 10
        const val COOLDOWN_SAMPLES = 5
        const val DOWN_STEP = 0.2
        const val UP_STEP = 0.1

        /** Never ask for less than a quarter of the configured bitrate. */
        const val MIN_SCALE = 0.25

        private val FRAME_RATE_LADDER = intArrayOf(24, 30, 60)

        fun nextFrameRateDown(current: Int): Int {
            val lower = FRAME_RATE_LADDER.filter { it < current }
            return lower.maxOrNull() ?: current
        }

        fun nextFrameRateUp(current: Int, ceiling: Int): Int {
            val higher = FRAME_RATE_LADDER.filter { it > current && it <= ceiling }
            return higher.minOrNull() ?: ceiling
        }
    }
}
