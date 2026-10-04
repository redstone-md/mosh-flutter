import Cocoa
import Darwin
import FlutterMacOS
import XCTest
@testable import mosh

class RunnerTests: XCTestCase {

  func testLaunchCallbackIgnoresBrokenPipeWithoutThrowing() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let previous = signal(SIGPIPE, SIG_DFL)
    defer { signal(SIGPIPE, previous) }
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
    XCTAssertEqual(raise(SIGPIPE), 0)
  }

  func testLocalizationPreservesCommandsAndSubmenus() {
    let menu = NSMenu(title: "Main")
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    edit.identifier = NSUserInterfaceItemIdentifier("nativeMenuEdit")
    let submenu = NSMenu(title: "Edit")
    edit.submenu = submenu
    menu.addItem(edit)
    let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    copy.identifier = NSUserInterfaceItemIdentifier("nativeMenuCopy")
    copy.tag = 7
    submenu.addItem(copy)
    let systemItem = NSMenuItem(title: "OS-owned", action: nil, keyEquivalent: "")
    submenu.addItem(systemItem)

    NativeMenuLocalizer.apply(["nativeMenuEdit": "Правка", "nativeMenuCopy": "Скопировать"], to: menu)
    XCTAssertEqual(edit.title, "Правка")
    XCTAssertEqual(submenu.title, "Правка")
    XCTAssertEqual(copy.title, "Скопировать")
    XCTAssertEqual(copy.action, #selector(NSText.copy(_:)))
    XCTAssertEqual(copy.keyEquivalent, "c")
    XCTAssertEqual(copy.tag, 7)
    XCTAssertEqual(systemItem.title, "OS-owned")
    XCTAssertTrue(menu.items[0] === edit)

    NativeMenuLocalizer.apply(["nativeMenuEdit": "Edit", "nativeMenuCopy": "Copy"], to: menu)
    XCTAssertEqual(copy.title, "Copy")
  }

  func testFullscreenLabelFollowsWindowState() {
    let menu = NSMenu(title: "View")
    let item = NSMenuItem(title: "Enter Full Screen", action: nil, keyEquivalent: "f")
    item.identifier = NSUserInterfaceItemIdentifier("nativeMenuEnterFullScreen")
    menu.addItem(item)
    let labels = ["nativeMenuEnterFullScreen": "На весь экран",
                  "nativeMenuExitFullScreen": "Выйти из полноэкранного режима"]
    NativeMenuLocalizer.apply(labels, to: menu, fullScreen: true)
    XCTAssertEqual(item.title, labels["nativeMenuExitFullScreen"])
    NativeMenuLocalizer.apply(labels, to: menu)
    XCTAssertEqual(item.title, labels["nativeMenuEnterFullScreen"])
  }

  func testApplicationMenuHasLocalizationIdentifiers() {
    let menu = NSApp.mainMenu!
    func identifiers(_ menu: NSMenu) -> [String] {
      menu.items.flatMap { item in
        (item.identifier.map { [$0.rawValue] } ?? [])
          + (item.submenu.map { identifiers($0) } ?? [])
      }
    }
    let ids = identifiers(menu)
    XCTAssertEqual(ids.filter { $0.hasPrefix("nativeMenu") }.count, 51,
                   "Loaded menu identifiers: \(ids)")
    XCTAssertTrue(ids.contains("nativeMenuCopy"))
    XCTAssertTrue(ids.contains("nativeMenuPreferencesAction"))
  }

}
