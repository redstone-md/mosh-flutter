import CryptoKit
import Foundation

/// The chats a message preview can come from, as the app left them
/// (lib/src/features/wake/wake_previews.dart), and opening one sealed by a
/// member (mosh-core/src/conversation/wake/preview.rs): AES-256-GCM,
/// base64url of nonce, ciphertext and tag over `{"text": …}`. The key that
/// opens it names the chat. Every member of a group knows its key, so a
/// group preview also carries its author's MLS signature, and the author
/// is the member whose key made it, under the name the app left for them.
struct PreviewBook {
  struct Chat: Decodable {
    let id: String
    let name: String
    let keys: [String]
    /// The group's other members; nil for a DM.
    let members: [Member]?

    private enum CodingKeys: String, CodingKey {
      case id = "chat"
      case name, keys, members
    }
  }

  struct Member: Decodable {
    /// Their MLS key, in base64.
    let key: String
    let name: String
  }

  struct Shown: Equatable {
    let chat: String
    let title: String
    let text: String
  }

  fileprivate struct Body: Decodable {
    let text: String
    let from: String?
    let sig: String?
  }

  let chats: [Chat]

  init?(json: Data) {
    guard let chats = try? JSONDecoder().decode([Chat].self, from: json) else { return nil }
    self.chats = chats
  }

  /// The chat whose key opens `preview`, with its text; nil when none does,
  /// or a group's preview is not signed by one of its members.
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
        if chat.members == nil {
          return Shown(chat: chat.id, title: chat.name, text: body.text)
        }
        return chat.signed(body)
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

extension PreviewBook.Chat {
  /// "Name: text" of a group preview a member of this group signed.
  fileprivate func signed(_ body: PreviewBook.Body) -> PreviewBook.Shown? {
    guard let from = body.from, let member = members?.first(where: { $0.key == from }),
      let raw = Data(base64Encoded: from),
      let signature = body.sig.flatMap({ Data(base64Encoded: $0) }),
      let author = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
      author.isValidSignature(
        signature, for: Self.signingInput(["mosh-group-preview-v1", id, body.text]))
    else { return nil }
    return PreviewBook.Shown(chat: id, title: name, text: "\(member.name): \(body.text)")
  }

  /// Each part as a 4-byte big-endian length and its UTF-8 bytes.
  static func signingInput(_ parts: [String]) -> Data {
    parts.reduce(into: Data()) { input, part in
      let bytes = Data(part.utf8)
      withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { input.append(contentsOf: $0) }
      input.append(bytes)
    }
  }
}
