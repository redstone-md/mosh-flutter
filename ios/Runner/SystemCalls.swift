import AVFoundation
import CallKit
import CryptoKit
import Flutter
import PushKit
import UIKit

/// The phone's own call screen (CallKit) and the VoIP pushes that start it,
/// for `lib/src/platform/ios_system_calls.dart`. A push names only a call id;
/// it is reported to CallKit at once, as iOS requires, under "Mosh" until the
/// app's call, received over Moss, names the caller. Calls stay out of the
/// Phone app's recents. Dart sends what its call looks like (`show`,
/// `ended`); this sends back what the user does (`answer`, `end`, `mute`),
/// held until Dart is `ready` when the user acts first.
final class SystemCalls: NSObject {
  static let shared = SystemCalls()

  /// A pushed call whose offer has not arrived by then stops ringing; the
  /// caller rings for 30 seconds.
  private static let offerWait: TimeInterval = 35

  private struct Call {
    let uuid: UUID
    var outgoing = false
    /// The app's own call stands behind it, not only a push.
    var confirmed = false
  }

  private let provider: CXProvider
  private let controller = CXCallController()
  private let voip = PKPushRegistry(queue: .main)
  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var waiting: [(String, [String: Any])] = []
  /// Changed on the main queue only; `hasCall` is read from audio threads.
  private var calls: [String: Call] = [:] {
    didSet {
      lock.lock()
      carrying = !calls.isEmpty
      lock.unlock()
    }
  }
  private let lock = NSLock()
  private var carrying = false
  private var voipToken: Data?
  var alertToken: Data? {
    didSet { channel?.invokeMethod("tokens", arguments: nil) }
  }

  /// Whether CallKit carries a call now; its audio then waits for CallKit.
  var hasCall: Bool {
    lock.lock()
    defer { lock.unlock() }
    return carrying
  }

  private override init() {
    let configuration = CXProviderConfiguration()
    configuration.includesCallsInRecents = false
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    provider = CXProvider(configuration: configuration)
    super.init()
    provider.setDelegate(self, queue: .main)
  }

  /// Listens for VoIP pushes. Called at launch: a push that launched the app
  /// is delivered once the registry has its delegate.
  func start() {
    voip.delegate = self
    voip.desiredPushTypes = [.voIP]
  }

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.mosh/system-calls", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["call"] as? String ?? ""
    switch call.method {
    case "ready":
      dartReady = true
      waiting.forEach { channel?.invokeMethod($0.0, arguments: $0.1) }
      waiting.removeAll()
    case "show":
      show(id, kind: args["kind"] as? String ?? "", name: args["name"] as? String ?? "")
    case "ended":
      if let ended = calls.removeValue(forKey: id) {
        provider.reportCall(with: ended.uuid, endedAt: nil, reason: .remoteEnded)
      }
    case "tokens":
      result(tokens())
      return
    case "loadRegistration":
      WakeKeychain.queue.async {
        let stored = WakeKeychain.load()
        DispatchQueue.main.async { result(stored) }
      }
      return
    case "saveRegistration":
      let registration = call.arguments as? String ?? ""
      WakeKeychain.queue.async {
        let status = WakeKeychain.save(registration)
        DispatchQueue.main.async {
          // Unsaved, the handle is not announced: after a restart the phone
          // could not reuse it.
          result(status == errSecSuccess
            ? nil : FlutterError(code: "keychain", message: "OSStatus \(status)", details: nil))
        }
      }
      return
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  private func show(_ id: String, kind: String, name: String) {
    let update = Self.update(name)
    switch kind {
    case "incoming":
      if let call = calls[id] {
        calls[id]?.confirmed = true
        provider.reportCall(with: call.uuid, updated: update)
      } else {
        reportIncoming(id, update: update, confirmed: true) {}
      }
    case "outgoing" where calls[id] == nil:
      let uuid = Self.uuid(id)
      calls[id] = Call(uuid: uuid, outgoing: true, confirmed: true)
      let start = CXStartCallAction(call: uuid, handle: update.remoteHandle!)
      controller.request(CXTransaction(action: start)) { [weak self] error in
        if error != nil {
          self?.forget(id)
        } else {
          self?.provider.reportCall(with: uuid, updated: update)
        }
      }
    case "active":
      if let call = calls[id], call.outgoing {
        provider.reportOutgoingCall(with: call.uuid, connectedAt: nil)
      }
    default:
      break
    }
  }

  /// Reports a call CallKit may already have: iOS wants every VoIP push
  /// reported, and the same call id is the same call, so "already exists"
  /// is success.
  private func reportIncoming(
    _ id: String, update: CXCallUpdate, confirmed: Bool, completion: @escaping () -> Void
  ) {
    let uuid = Self.uuid(id)
    if calls[id] == nil { calls[id] = Call(uuid: uuid, confirmed: confirmed) }
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      let known = (error as? CXErrorCodeIncomingCallError)?.code == .callUUIDAlreadyExists
      // Do Not Disturb or a blocked caller: the app's own screen still rings.
      if let error = error, !known {
        NSLog("mosh: CallKit refused call %@: %@", id, error.localizedDescription)
        self?.forget(id)
      }
      completion()
    }
  }

  private func forget(_ id: String) {
    calls[id] = nil
  }

  private func send(_ method: String, _ arguments: [String: Any]) {
    if dartReady, let channel = channel {
      channel.invokeMethod(method, arguments: arguments)
    } else {
      waiting.append((method, arguments))
    }
  }

  private func id(for uuid: UUID) -> String? {
    calls.first { $0.value.uuid == uuid }?.key
  }

  private func tokens() -> [String: String]? {
    guard let voip = voipToken else { return nil }
    #if DEBUG
      let environment = "sandbox"
    #else
      let environment = "production"
    #endif
    var tokens = ["voip": Self.hex(voip), "environment": environment]
    if let alert = alertToken { tokens["apns"] = Self.hex(alert) }
    return tokens
  }

  private static func update(_ name: String) -> CXCallUpdate {
    let update = CXCallUpdate()
    let shown = name.isEmpty ? "Mosh" : name
    update.remoteHandle = CXHandle(type: .generic, value: shown)
    update.localizedCallerName = shown
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    return update
  }

  /// The same call id gives the same CallKit call, so a push and the offer
  /// that follows it are one call.
  static func uuid(_ callId: String) -> UUID {
    let digest = Array(SHA256.hash(data: Data(callId.utf8)))
    return NSUUID(uuidBytes: digest) as UUID
  }

  private static func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}

extension SystemCalls: PKPushRegistryDelegate {
  func pushRegistry(
    _ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType
  ) {
    voipToken = credentials.token
    channel?.invokeMethod("tokens", arguments: nil)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    voipToken = nil
  }

  /// iOS ends an app that leaves a VoIP push without a reported call, so
  /// every push reports one, even a malformed one, which ends at once.
  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType, completion: @escaping () -> Void
  ) {
    let id = payload.dictionaryPayload["call"] as? String ?? UUID().uuidString
    NSLog("mosh: VoIP push for call %@", id)
    let known = calls[id] != nil
    reportIncoming(id, update: Self.update(""), confirmed: false, completion: completion)
    guard !known else { return }
    let wait = payload.dictionaryPayload["call"] == nil ? 0 : Self.offerWait
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      guard let self = self, let call = self.calls[id], !call.confirmed else { return }
      self.calls[id] = nil
      self.provider.reportCall(with: call.uuid, endedAt: nil, reason: .unanswered)
    }
  }
}

extension SystemCalls: CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    for id in calls.keys { send("end", ["call": id]) }
    calls.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    CallKitAudio.prepare()
    if let id = id(for: action.callUUID) { send("answer", ["call": id]) }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    CallKitAudio.prepare()
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    if let id = id(for: action.callUUID) {
      calls[id] = nil
      send("end", ["call": id])
    }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    if let id = id(for: action.callUUID) { send("mute", ["call": id, "muted": action.isMuted]) }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    CallKitAudio.shared.activated(audioSession)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    CallKitAudio.shared.deactivated(audioSession)
  }
}

/// The wake registration (handle and secret), kept where only this app on
/// this phone reads it, and readable while the phone is locked after its
/// first unlock, when a push starts the app. A Keychain call can wait on
/// securityd for seconds, so they run in order on their own queue, never on
/// the main thread.
enum WakeKeychain {
  static let queue = DispatchQueue(label: "app.mosh.wake-keychain")

  private static let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "app.mosh.wake",
    kSecAttrAccount as String: "registration",
  ]

  static func load() -> String? {
    var found = query
    found[kSecReturnData as String] = true
    var item: CFTypeRef?
    guard SecItemCopyMatching(found as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ registration: String) -> OSStatus {
    SecItemDelete(query as CFDictionary)
    var item = query
    item[kSecValueData as String] = Data(registration.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(item as CFDictionary, nil)
  }
}
