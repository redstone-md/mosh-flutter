import Foundation

/// The platform side of a call for mosh-core's call owner
/// (`mosh-core/src/mobile_media.rs`): the audio route and the camera. Rust
/// sends one JSON command and takes its JSON answer; the call itself, its
/// engine and its media stay in Rust.
enum CallMedia {
  private typealias Command = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
  private typealias Register = @convention(c) (Command) -> Void

  static let audio = CallAudio()
  static let camera = CallCamera()

  /// Hands mosh-core the command function. mosh-core is linked into the app,
  /// so its exports resolve without a handle.
  static func register() {
    guard let register: Register = symbol("mosh_ios_media_register") else { return }
    register { json in strdup(CallMedia.answer(String(cString: json))) }
  }

  /// A C function mosh-core exports, as `T`.
  static func symbol<T>(_ name: String) -> T? {
    // RTLD_DEFAULT: every image loaded into the process.
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
  }

  private static func answer(_ json: String) -> String {
    let result: [String: Any]
    do {
      guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
      else { throw CallMediaError.malformed }
      result = try perform(value)
    } catch {
      result = ["error": String(describing: error)]
    }
    let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
  }

  private static func perform(_ value: [String: Any]) throws -> [String: Any] {
    switch value["action"] as? String {
    case "devices": return audio.devices()
    case "select": return audio.select(output: value["output"] as? String, input: value["input"] as? String)
    case "audioStop": audio.stop()
    case "cameras": return ["cameras": camera.devices()]
    case "cameraStart":
      camera.start(id: value["id"] as? String, generation: (value["generation"] as? NSNumber)?.uint64Value ?? 0)
    case "cameraStop": camera.stop()
    default: throw CallMediaError.unknownAction
    }
    return [:]
  }
}

enum CallMediaError: Error {
  case malformed, unknownAction, noCamera
}
