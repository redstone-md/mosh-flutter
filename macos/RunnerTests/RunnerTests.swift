import Cocoa
import Darwin
import FlutterMacOS
import XCTest
@testable import mosh

class RunnerTests: XCTestCase {

  @MainActor
  func testLaunchCallbackIgnoresBrokenPipeWithoutThrowing() async throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let previous = signal(SIGPIPE, SIG_DFL)
    defer { signal(SIGPIPE, previous) }
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp))
    XCTAssertEqual(raise(SIGPIPE), 0)
  }

  @MainActor
  func testLocalizationPreservesCommandsAndSubmenus() async {
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

  @MainActor
  func testFullscreenLabelFollowsWindowState() async {
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

  @MainActor
  func testApplicationMenuHasLocalizationIdentifiers() async {
    let menu = NSApp.mainMenu!
    func identifiers(_ menu: NSMenu) -> [String] {
      menu.items.flatMap { item in
        (item.identifier.map { [$0.rawValue] } ?? [])
          + (item.submenu.map { identifiers($0) } ?? [])
      }
    }
    let ids = identifiers(menu)
    // AppKit may add an alternate Full Screen item with the same identifier.
    let localizationIds = Set(ids.filter { $0.hasPrefix("nativeMenu") })
    XCTAssertEqual(localizationIds.count, 51,
                   "Loaded menu identifiers: \(ids)")
    XCTAssertTrue(ids.contains("nativeMenuCopy"))
    XCTAssertTrue(ids.contains("nativeMenuPreferencesAction"))
  }

  @MainActor
  func testApplicationMenuLocalizesEveryMatchingItem() async throws {
    let menu = try XCTUnwrap(NSApp.mainMenu)
    func items(_ menu: NSMenu) -> [NSMenuItem] {
      menu.items.flatMap { [$0] + ($0.submenu.map { items($0) } ?? []) }
    }
    let localized = items(menu).filter { $0.identifier?.rawValue.hasPrefix("nativeMenu") == true }
    let originals = localized.map { ($0, $0.title, $0.submenu?.title) }
    defer {
      for (item, title, submenuTitle) in originals {
        item.title = title
        if let title = submenuTitle { item.submenu?.title = title }
      }
    }
    let labels = Dictionary(uniqueKeysWithValues: Set(localized.compactMap { $0.identifier?.rawValue })
      .map { ($0, "Localized \($0)") })
    NativeMenuLocalizer.apply(labels, to: menu)
    XCTAssertFalse(localized.isEmpty)
    for item in localized {
      XCTAssertEqual(item.title, labels[item.identifier!.rawValue])
      if let submenu = item.submenu { XCTAssertEqual(submenu.title, item.title) }
    }
  }

  func testCallVideoTextureShowsPresentedFramesAsBgraSurfaces() throws {
    typealias Present = @convention(c) (
      UnsafeRawPointer, UnsafePointer<UInt8>, UInt32, UInt32
    ) -> Void
    let textures = RecordingTextures()
    let texture = CallVideoTexture(registry: textures)
    XCTAssertNil(texture.copyPixelBuffer())
    // As Rust calls it: the export's first word is the present function.
    let present = texture.exported.load(as: Present.self)

    let rgba: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
    present(texture.exported, rgba, 2, 1)
    let shown = try XCTUnwrap(texture.copyPixelBuffer()).takeRetainedValue()
    XCTAssertEqual(CVPixelBufferGetPixelFormatType(shown), kCVPixelFormatType_32BGRA)
    XCTAssertNotNil(CVPixelBufferGetIOSurface(shown))
    CVPixelBufferLockBaseAddress(shown, .readOnly)
    let row = try XCTUnwrap(CVPixelBufferGetBaseAddress(shown))
      .assumingMemoryBound(to: UInt8.self)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: row, count: 8)), [3, 2, 1, 4, 7, 6, 5, 8])
    CVPixelBufferUnlockBaseAddress(shown, .readOnly)
    XCTAssertEqual(textures.available, [texture.id])

    present(texture.exported, [UInt8](repeating: 9, count: 16), 2, 2)
    let resized = try XCTUnwrap(texture.copyPixelBuffer()).takeRetainedValue()
    XCTAssertEqual(CVPixelBufferGetHeight(resized), 2)
    XCTAssertEqual(CVPixelBufferGetHeight(shown), 1, "a frame the engine holds is not rewritten")
  }
}

private final class RecordingTextures: NSObject, FlutterTextureRegistry {
  var available: [Int64] = []
  func register(_ texture: FlutterTexture) -> Int64 { 7 }
  func textureFrameAvailable(_ textureId: Int64) { available.append(textureId) }
  func unregisterTexture(_ textureId: Int64) {}
}
