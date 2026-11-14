import AVFoundation
import UIKit

/// Where a call plays on iPhone: the receiver, the speaker or a headset.
/// libwebrtc's audio module records and plays in the voice-chat session it
/// configures; this only picks the route, as the system call screen does,
/// and darkens the screen against the ear while a call runs.
final class CallAudio {
  private static let receiver = "ios:receiver"
  private static let speaker = "ios:speaker"
  /// The one microphone a call offers: the route's own, like Android's.
  private static let routeInput = "ios:route-input"

  private let queue = DispatchQueue(label: "app.mosh.call-audio")
  /// The output the call picked; nil follows the system route.
  private var output: String?
  private var routeChanges: NSObjectProtocol?
  /// The session as it was before the call, restored after it, so playback
  /// after a call leaves the receiver.
  private var previous: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

  func devices() -> [String: Any] {
    queue.sync {
      let session = AVAudioSession.sharedInstance()
      var outputs: [[String: String]] = []
      if UIDevice.current.userInterfaceIdiom == .phone {
        outputs.append(["id": Self.receiver, "name": "iPhone"])
      }
      outputs.append(["id": Self.speaker, "name": "Speaker"])
      for port in session.availableInputs ?? [] where port.portType != .builtInMic {
        outputs.append(["id": "ios:\(port.uid)", "name": port.portName])
      }
      let inputs = session.isInputAvailable
        ? [["id": Self.routeInput, "name": "Microphone (selected audio route)"]] : []
      return ["inputs": inputs, "outputs": outputs]
    }
  }

  func select(output: String?, input: String?) -> [String: Any] {
    queue.sync {
      if routeChanges == nil { begin() }
      self.output = output
      let inputOk = AVAudioSession.sharedInstance().isInputAvailable
        && (input == nil || input == Self.routeInput)
      return ["input_ok": inputOk, "output_ok": apply()]
    }
  }

  func stop() {
    queue.sync {
      guard let observer = routeChanges else { return }
      NotificationCenter.default.removeObserver(observer)
      routeChanges = nil
      output = nil
      apply()
      if let previous = previous {
        try? AVAudioSession.sharedInstance().setCategory(previous.0, mode: previous.1, options: previous.2)
      }
      previous = nil
      DispatchQueue.main.async { UIDevice.current.isProximityMonitoringEnabled = false }
    }
  }

  /// The session libwebrtc sets up, set up first so a route can be picked
  /// before its audio module starts. A category change drops the picked
  /// route, so it is applied again after one.
  private func begin() {
    let session = AVAudioSession.sharedInstance()
    previous = (session.category, session.mode, session.categoryOptions)
    try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    routeChanges = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
    ) { [weak self] notification in
      let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
        .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
      guard reason == .categoryChange, let self = self else { return }
      self.queue.async { self.apply() }
    }
    DispatchQueue.main.async { UIDevice.current.isProximityMonitoringEnabled = true }
  }

  @discardableResult
  private func apply() -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      switch output {
      case nil:
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(nil)
      case Self.speaker?:
        try session.setPreferredInput(nil)
        try session.overrideOutputAudioPort(.speaker)
      case Self.receiver?:
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(session.availableInputs?.first { $0.portType == .builtInMic })
      case let id?:
        // A headset plays where its microphone is: preferring the input
        // moves the output with it.
        guard let port = session.availableInputs?.first(where: { "ios:\($0.uid)" == id })
        else { return false }
        try session.overrideOutputAudioPort(.none)
        try session.setPreferredInput(port)
      }
      return true
    } catch {
      return false
    }
  }
}
