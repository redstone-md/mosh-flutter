import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Suppress SIGPIPE process-wide so that broken-pipe writes from CPAL audio
    // streams or Moss P2P networking return EPIPE instead of crashing the app.
    signal(SIGPIPE, SIG_IGN)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
