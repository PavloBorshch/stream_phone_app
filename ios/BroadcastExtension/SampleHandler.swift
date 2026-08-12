import ReplayKit

/// Runs in its own process, started only via RPSystemBroadcastPickerView
/// (see BroadcastPickerViewFactory.swift in the main app). This is
/// capture-only for now: every video sample buffer is counted and status is
/// relayed to the main app through the shared App Group container, but no
/// frame data is sent anywhere yet - that's future work once a transport
/// layer exists.
///
/// NOT YET WIRED INTO AN XCODE TARGET. Per the implementation plan, adding
/// the actual "Broadcast Upload Extension" target has to be done in Xcode
/// (File > New > Target) since that scaffolding can't be hand-authored via
/// project.pbxproj text edits. Once that target exists, replace its
/// generated SampleHandler.swift with this file's contents.
class SampleHandler: RPBroadcastSampleHandler {
    // TODO: replace with a real App Group id once the app has a real
    // (non com.example.*) bundle identifier. Must match Runner.entitlements,
    // BroadcastExtension.entitlements and ScreencastChannel.swift.
    private let appGroupID = "group.com.example.stream_phone_cam.shared"
    private let statusChangedNotificationName = "com.streamphonecam.broadcast.statusChanged" as CFString

    private var frameCount = 0

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        frameCount = 0
        defaults?.set(true, forKey: "isBroadcasting")
        defaults?.set(false, forKey: "isPaused")
        defaults?.set(Date().timeIntervalSince1970, forKey: "broadcastStartedAt")
        defaults?.set(0, forKey: "frameCount")
        defaults?.removeObject(forKey: "lastError")
        notifyStatusChanged()
    }

    override func broadcastPaused() {
        defaults?.set(true, forKey: "isPaused")
        notifyStatusChanged()
    }

    override func broadcastResumed() {
        defaults?.set(false, forKey: "isPaused")
        notifyStatusChanged()
    }

    override func broadcastFinished() {
        defaults?.set(false, forKey: "isBroadcasting")
        notifyStatusChanged()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        frameCount += 1

        // Throttle App Group writes to roughly once a second at ~30fps
        // rather than on every frame.
        if frameCount % 30 == 0 {
            defaults?.set(frameCount, forKey: "frameCount")
            defaults?.set(Date().timeIntervalSince1970, forKey: "lastFrameAt")
            notifyStatusChanged()
        }
    }

    private func notifyStatusChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(statusChangedNotificationName),
            nil,
            nil,
            true
        )
    }
}
