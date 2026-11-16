import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var callVideo: CallVideo?
  private var callPermissions: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A write to a socket or pipe whose peer is gone raises SIGPIPE, which
    // kills the app unless ignored; ignored, the write returns EPIPE. Moss's
    // networking and the audio streams rely on that, as on macOS.
    signal(SIGPIPE, SIG_IGN)
    CallMedia.register()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "MoshCallVideo") {
      callVideo = CallVideo(registrar: registrar)
      callPermissions = CallCamera.handlePermissions(registrar.messenger())
    }
  }
}
