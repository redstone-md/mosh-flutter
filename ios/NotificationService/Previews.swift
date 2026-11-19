import CryptoKit
import Foundation

/// The chats a message preview can come from, as the app left them
/// (lib/src/features/wake/wake_previews.dart), and opening one sealed by a
/// contact (mosh-core/src/private_dm_runtime/wake_preview.rs): AES-256-GCM,
/// base64url of nonce, ciphertext and tag over `{"text": …}`. The key that
/// opens it names the chat.
struct PreviewBook {
  struct Chat: Decodable {
    let session: String
    let name: String
    let keys: [String]
  }

  struct Shown: Equatable {
    let session: String
    let name: String
    let text: String
  }

  private struct Body: Decodable {
    let text: String
  }

  let chats: [Chat]

  init?(json: Data) {
    guard let chats = try? JSONDecoder().decode([Chat].self, from: json) else { return nil }
    self.chats = chats
  }

  /// The chat whose key opens `preview`, with its text; nil when none does.
  func open(_ preview: String) -> Shown? {
    guard let sealed = Self.base64URL(preview),
      let box = try? AES.GCM.SealedBox(combined: sealed)
    else { return nil }
    for chat in chats {
      for key in chat.keys {
        guard let raw = Data(base64Encoded: key), raw.count == 32,
          let plain = try? AES.GCM.open(box, using: SymmetricKey(data: raw)),
          let body = try? JSONDecoder().decode(Body.self, from: plain)
        else { continue }
        return Shown(session: chat.session, name: chat.name, text: body.text)
      }
    }
    return nil
  }

  private static func base64URL(_ text: String) -> Data? {
    var base64 = text.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    return Data(base64Encoded: base64)
  }
}
