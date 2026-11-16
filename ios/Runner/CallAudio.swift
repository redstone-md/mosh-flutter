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
  /// Outputs that are a headset rather than the phone itself.
  private static let external: Set<AVAudioSession.Port> =
    [.headphones, .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .usbAudio, .carAudio]

  private let queue = DispatchQueue(label: "app.mosh.call-audio")
  /// The output the call picked; nil follows the system route.
  private var output: String?
  private var routeChanges: NSObjectProtocol?
  /// Why the system last rerouted the call, for the field log.
  private var lastChange: AVAudioSession.RouteChangeReason?
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
      // Before a call the session is not .playAndRecord, so a Bluetooth
      // headset is not an input yet; the route still names it.
      let listed = Set(outputs.compactMap { $0["id"] })
      for port in session.currentRoute.outputs where Self.external.contains(port.portType)
        && !listed.contains("ios:\(port.uid)") {
        outputs.append(["id": "ios:\(port.uid)", "name": port.portName])
      }
      let inputs = session.isInputAvailable
        ? [["id": Self.routeInput, "name": "Microphone (selected audio route)"]] : []
      return ["inputs": inputs, "outputs": outputs, "route": route()]
    }
  }

  func select(output: String?, input: String?) -> [String: Any] {
    queue.sync {
      let webrtc = routeChanges == nil ? begin() : nil
      self.output = output
      let inputOk = AVAudioSession.sharedInstance().isInputAvailable
        && (input == nil || input == Self.routeInput)
      var reply: [String: Any] = ["input_ok": inputOk, "output_ok": apply()]
      reply["webrtc_session"] = webrtc
      return reply
    }
  }

  func stop() {
    queue.sync {
      guard let observer = routeChanges else { return }
      NotificationCenter.default.removeObserver(observer)
      routeChanges = nil
      output = nil
      lastChange = nil
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
  /// route, so it is applied again after one. Answers how libwebrtc was
  /// told the same session.
  private func begin() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    previous = (session.category, session.mode, session.categoryOptions)
    try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    routeChanges = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
    ) { [weak self] notification in
      let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
        .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
      // A headset plugged in or out reroutes the call and clears the
      // speaker override; the pick is applied again so what plays stays
      // what the call shows. A picked headset that left fails here, and the
      // next device refresh drops it.
      let reroutes: [AVAudioSession.RouteChangeReason] =
        [.categoryChange, .newDeviceAvailable, .oldDeviceUnavailable]
      guard let reason = reason, let self = self else { return }
      self.queue.async {
        // An override is this class applying the pick, not the system.
        if reason != .override { self.lastChange = reason }
        if reroutes.contains(reason) { self.apply() }
      }
    }
    DispatchQueue.main.async { UIDevice.current.isProximityMonitoringEnabled = true }
    let webrtc = Self.configureWebRTC()
    DispatchQueue.main.async { CallKitAudio.shared.sync() }
    return webrtc
  }

  /// libwebrtc's audio module applies its own session configuration when it
  /// starts. The webrtc-sdk build copies that configuration from whatever
  /// the session was when libwebrtc first looked: the app's playback-only
  /// default, with no input channel. The voice unit then could neither
  /// record nor play. A full call configuration (upstream's values) is
  /// installed before the module starts; the class lives in
  /// MoshMedia.framework, loaded by the time a call selects. Answers what
  /// libwebrtc held before and after, for the field log.
  private static func configureWebRTC() -> [String: Any] {
    let values: KeyValuePairs<String, Any> = [
      "category": AVAudioSession.Category.playAndRecord.rawValue,
      "mode": AVAudioSession.Mode.voiceChat.rawValue,
      "categoryOptions": AVAudioSession.CategoryOptions.allowBluetoothHFP.rawValue,
      "sampleRate": 48_000.0,
      "ioBufferDuration": 0.02,
      "inputNumberOfChannels": 1,
      "outputNumberOfChannels": 1,
    ]
    guard let type = NSClassFromString("RTCAudioSessionConfiguration") as? NSObject.Type
    else { return ["error": "RTCAudioSessionConfiguration missing"] }
    let current = (type as AnyObject)
      .perform(NSSelectorFromString("webRTCConfiguration"))?.takeUnretainedValue() as? NSObject
    let call = type.init()
    for (key, value) in values { call.setValue(value, forKey: key) }
    _ = (type as AnyObject).perform(NSSelectorFromString("setWebRTCConfiguration:"), with: call)
    func describe(_ configuration: NSObject?) -> [String: String] {
      Dictionary(uniqueKeysWithValues: values.map(\.key).map { key in
        (key, configuration.map { "\($0.value(forKey: key) ?? "nil")" } ?? "nil")
      })
    }
    return ["before": describe(current), "after": describe(call)]
  }

  /// Where the call plays right now and how loud, for the call's status
  /// line in the field log: the system's route, its volume (the receiver
  /// keeps its own), the pick and the last reroute. Called on the queue.
  private func route() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    return [
      "outputs": session.currentRoute.outputs.map { $0.portType.rawValue },
      "inputs": session.currentRoute.inputs.map { $0.portType.rawValue },
      "volume": (session.outputVolume * 100).rounded() / 100,
      "category": session.category.rawValue,
      "mode": session.mode.rawValue,
      "picked": output ?? "system",
      "last_change": lastChange.map(Self.name) ?? "none",
    ]
  }

  private static func name(_ reason: AVAudioSession.RouteChangeReason) -> String {
    switch reason {
    case .newDeviceAvailable: return "newDeviceAvailable"
    case .oldDeviceUnavailable: return "oldDeviceUnavailable"
    case .categoryChange: return "categoryChange"
    case .override: return "override"
    case .wakeFromSleep: return "wakeFromSleep"
    case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
    case .routeConfigurationChange: return "routeConfigurationChange"
    case .unknown: return "unknown"
    @unknown default: return "\(reason.rawValue)"
    }
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

/// Under CallKit the system activates the call's audio session, so
/// libwebrtc's audio waits for it (manual audio) rather than activating the
/// session itself. libwebrtc's `RTCAudioSession` lives in
/// MoshMedia.framework, which Rust loads with the first call, often after
/// CallKit activated the session; whichever comes second applies it.
final class CallKitAudio {
  static let shared = CallKitAudio()

  private var session: AVAudioSession?
  /// libwebrtc was told of the current activation.
  private var told = false

  /// The category a call needs, set before CallKit activates the session.
  static func prepare() {
    try? AVAudioSession.sharedInstance()
      .setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
  }

  func activated(_ session: AVAudioSession) {
    self.session = session
    told = false
    sync()
  }

  func deactivated(_ session: AVAudioSession) {
    if told { _ = Self.rtc()?.perform(NSSelectorFromString("audioSessionDidDeactivate:"), with: session) }
    self.session = nil
    told = false
    sync()
  }

  /// Applies the CallKit state to libwebrtc once its class is loaded. A call
  /// that CallKit does not carry keeps libwebrtc's own audio handling.
  func sync() {
    guard let rtc = Self.rtc() else { return }
    let manual = SystemCalls.shared.hasCall
    rtc.setValue(manual, forKey: "useManualAudio")
    if manual, let session = session, !told {
      _ = rtc.perform(NSSelectorFromString("audioSessionDidActivate:"), with: session)
      told = true
    }
    rtc.setValue(!manual || session != nil, forKey: "isAudioEnabled")
  }

  private static func rtc() -> NSObject? {
    guard let type = NSClassFromString("RTCAudioSession") as? NSObject.Type else { return nil }
    return (type as AnyObject).perform(NSSelectorFromString("sharedInstance"))?
      .takeUnretainedValue() as? NSObject
  }
}
