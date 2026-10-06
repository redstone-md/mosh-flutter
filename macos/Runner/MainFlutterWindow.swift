import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private var menuLocalizer: NativeMenuLocalizer?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }
    menuLocalizer = NativeMenuLocalizer(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Only labels change; responder-chain actions, native menus and shortcuts stay
/// owned by Cocoa. Identifiers are declared on the original XIB menu items.
class NativeMenuLocalizer: NSObject {
  private let channel: FlutterMethodChannel
  private var labels: [String: String] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mosh/interface-menu", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "localize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let labels = call.arguments as? [String: String] else {
        result(FlutterError(code: "invalid-menu-labels", message: "Expected menu labels", details: nil))
        return
      }
      self?.labels = labels
      self?.update()
      result(nil)
    }
    for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowStateChanged(_:)), name: name, object: nil)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func windowStateChanged(_ notification: Notification) {
    update()
  }

  private func update() {
    guard let menu = NSApp.mainMenu else { return }
    Self.apply(labels, to: menu, fullScreen: NSApp.keyWindow?.styleMask.contains(.fullScreen) == true)
  }

  static func apply(_ labels: [String: String], to menu: NSMenu, fullScreen: Bool = false) {
    for item in menu.items {
      if let identifier = item.identifier?.rawValue {
        let key = identifier == "nativeMenuEnterFullScreen" && fullScreen
          ? "nativeMenuExitFullScreen" : identifier
        if let title = labels[key] {
          item.title = title
          item.submenu?.title = title
        }
      }
      if let submenu = item.submenu {
        apply(labels, to: submenu, fullScreen: fullScreen)
      }
    }
  }
}
