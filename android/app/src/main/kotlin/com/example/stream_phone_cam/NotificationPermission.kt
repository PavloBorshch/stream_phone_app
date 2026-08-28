package com.example.stream_phone_cam

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Asks for POST_NOTIFICATIONS when the app is about to do something that
 * depends on a visible notification.
 *
 * Both capture paths need it, for different reasons: a foreground service is
 * required to show an ongoing notification, and the connection-lost alert
 * (PLAN.md Phase 7) is worthless without it — it exists precisely for when the
 * user is not looking at the app. Shared rather than duplicated so the two
 * paths cannot drift apart.
 *
 * Deliberately fire-and-forget: the result is not awaited because neither
 * capture nor publishing should be blocked on it. A user who declines still
 * gets a working stream, just without the alerts.
 */
object NotificationPermission {
    const val REQUEST_CODE = 4202

    fun requestIfNeeded(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return

        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE,
        )
    }
}
