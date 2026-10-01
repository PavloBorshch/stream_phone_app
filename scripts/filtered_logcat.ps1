<#
.SYNOPSIS
    Tails `adb logcat` with the IMGSRV driver noise silenced.

.DESCRIPTION
    On PowerVR/MediaTek devices (see third_party/HaishinKit.kt/PATCH_NOTES.md's
    "Producer/consumer fence sync" section) the GPU driver logs
    `E/IMGSRV: ScheduleTA: Skipping render from different gc/thread!` (plus a
    couple of sibling IMGSRV lines) continuously while streaming — expected,
    not a regression, and loud enough to bury everything else in the console.

    `flutter run`'s own terminal relays the running app's raw device logcat
    lines alongside Dart output, but it does not expose any tag-level
    filtering — there is no `flutter run` flag that maps to logcat's
    `<tag>:<priority>` filter spec, so this noise cannot be suppressed from
    inside `flutter run` itself. Use this script in a second terminal instead:
    keep `flutter run` in one terminal for Dart output/hot reload, and this
    one for watching native/driver logs without the IMGSRV flood.

    Logcat filter spec used: `IMGSRV:S *:V` — silence (S) the IMGSRV tag
    specifically, verbose (V, i.e. everything) for every other tag.

.PARAMETER Serial
    Optional device serial (see `adb devices`) to target when more than one
    device/emulator is attached. Omit to use adb's default (errors if more
    than one device is connected and none specified).

.EXAMPLE
    scripts/filtered_logcat.ps1

.EXAMPLE
    scripts/filtered_logcat.ps1 -Serial emulator-5554
#>
param(
    [string]$Serial
)

$adbArgs = @()
if ($Serial) {
    $adbArgs += @('-s', $Serial)
}
$adbArgs += @('logcat', 'IMGSRV:S', '*:V')

& adb @adbArgs
