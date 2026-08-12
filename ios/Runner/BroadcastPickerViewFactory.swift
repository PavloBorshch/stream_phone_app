import Flutter
import ReplayKit
import UIKit

/// Exposes RPSystemBroadcastPickerView as a Flutter platform view. This is
/// the only Apple-sanctioned way to start a third-party broadcast extension -
/// programmatic start is disallowed - so the Dart side embeds this view
/// directly as the Screencast record button on iOS rather than driving
/// start/stop through a method channel.
final class BroadcastPickerViewFactory: NSObject, FlutterPlatformViewFactory {
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        BroadcastPickerPlatformView(frame: frame)
    }
}

final class BroadcastPickerPlatformView: NSObject, FlutterPlatformView {
    private let picker: RPSystemBroadcastPickerView

    init(frame: CGRect) {
        picker = RPSystemBroadcastPickerView(frame: frame)
        // TODO: replace with the real BroadcastExtension bundle identifier
        // once the app has a real (non com.example.*) bundle id.
        picker.preferredExtensionBundleIdentifier = "com.example.stream_phone_cam.BroadcastExtension"
        picker.showsMicrophoneButton = false
        picker.tintColor = .systemRed
        super.init()
    }

    func view() -> UIView {
        picker
    }
}
