import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private let screencastChannel = ScreencastChannel()
  private let lanDiscoveryChannel = LanDiscoveryChannel()

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreencastPlugin")
    screencastChannel.register(messenger: registrar.messenger())
    registrar.register(BroadcastPickerViewFactory(), withId: "com.streamphonecam/broadcast_picker_view")

    let lanDiscoveryRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "LanDiscoveryPlugin")
    lanDiscoveryChannel.register(messenger: lanDiscoveryRegistrar.messenger())
  }
}
