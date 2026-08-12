import Flutter

/// Bridges the main app to the Screencast Broadcast Upload Extension, which
/// runs in a separate process and can't call into Dart directly. The
/// extension (see ios/BroadcastExtension/SampleHandler.swift) writes status
/// into a shared App Group container and posts a Darwin notification; this
/// class listens for that notification and relays the current status to
/// Dart over an EventChannel.
final class ScreencastChannel: NSObject, FlutterStreamHandler {
    // TODO: replace with a real App Group id once the app has a real
    // (non com.example.*) bundle identifier. Must match Runner.entitlements,
    // BroadcastExtension.entitlements and SampleHandler.swift.
    private let appGroupID = "group.com.example.stream_phone_cam.shared"
    private let statusChangedNotificationName = "com.streamphonecam.broadcast.statusChanged" as CFString

    private var eventSink: FlutterEventSink?

    func register(messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(
            name: "com.streamphonecam/screencast",
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "getStatus":
                result(self?.currentStatus() ?? [:])
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let eventChannel = FlutterEventChannel(
            name: "com.streamphonecam/screencast_events",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<ScreencastChannel>.fromOpaque(observer).takeUnretainedValue().emitStatus()
            },
            statusChangedNotificationName,
            nil,
            .deliverImmediately
        )
    }

    private func currentStatus() -> [String: Any] {
        let defaults = UserDefaults(suiteName: appGroupID)
        let isBroadcasting = defaults?.bool(forKey: "isBroadcasting") ?? false
        let isPaused = defaults?.bool(forKey: "isPaused") ?? false
        let status: String
        if !isBroadcasting {
            status = "idle"
        } else if isPaused {
            status = "paused"
        } else {
            status = "capturing"
        }
        return [
            "status": status,
            "frameCount": defaults?.integer(forKey: "frameCount") ?? 0,
        ]
    }

    private func emitStatus() {
        eventSink?(currentStatus())
    }

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        emitStatus()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
