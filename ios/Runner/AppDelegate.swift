import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// The process's one engine, running from launch. A call push starts the
  /// app with no scene and no window, and the call must ring, connect and
  /// play before one exists; the scene shows this engine when it connects.
  lazy var engine = FlutterEngine(name: "mosh")
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
    SystemCalls.shared.start()
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    if let registrar = engine.registrar(forPlugin: "MoshCallVideo") {
      callVideo = CallVideo(registrar: registrar)
      callPermissions = CallCamera.handlePermissions(registrar.messenger())
    }
    SystemCalls.shared.attach(engine.binaryMessenger)
    // The token for "New message" alerts; showing them needs the
    // notification permission the app asks for on its own.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    SystemCalls.shared.alertToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
