import CryptoKit
import Foundation

// Opens the previews mosh-core pins in
// the_sealed_forms_are_what_the_notification_extension_opens
// (mosh-core/src/conversation/wake/preview_tests.rs), as Android's
// MoshPreviewBookTest does, so a change to the sealed form on any side fails
// one of the three.
let key = Data(repeating: 7, count: 32).base64EncodedString()
let other = Data(repeating: 8, count: 32).base64EncodedString()
let direct =
  "CQkJCQkJCQkJCQkJXKfw8caE41uCslTpZjobD2Zg1iK2spmoANlmx6cRIQO8kNjhn4iTe0muP9iBv9ClUiO7XJs"
let group =
  "CQkJCQkJCQkJCQkJXKfi5tGd41uCAKVXhdnwsqPEV9xmoYGUKfkfiaNNTkKiiZ-ZlwJhcgaG9WB8TrqWLQOx0S-2gm"
  + "wWBma1bDQ_uhQYwzu7ZJbO76GLJPCRvLpJ3YFiyXSexA_sD9wd5m4YSEmi1J9y5zp7jN4xHIwPJs9fXD7S4Im7G_m8"
  + "mnsxD5H6_08hHsknjiw3iZUdkHHgVbsiKs9u9mB7UcjnyJ41s8v2ON60Oao-ZaIVx0b_HXvM2cCzRLo7f_nExFKwBi"
  + "2FohBd6f5T9nelWQC4"
let mia = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 5, count: 32))
let miaKey = mia.publicKey.rawRepresentation.base64EncodedString()
let stranger = Curve25519.Signing.PrivateKey()

func book(_ keys: [String], members: [[String: String]]? = nil) -> PreviewBook {
  var chat: [String: Any] = ["chat": "s1", "name": "Alice", "keys": keys]
  if let members {
    chat = ["chat": "group-1", "name": "Hikes", "keys": keys, "members": members]
  }
  return PreviewBook(json: try! JSONSerialization.data(withJSONObject: [chat]))!
}

/// A group preview sealed under `key`, claiming Mia's key but signed by
/// `signer`.
func forged(by signer: Curve25519.Signing.PrivateKey) -> String {
  let text = "send me the code"
  let input = PreviewBook.Chat.signingInput(["mosh-group-preview-v1", "group-1", text])
  let body: [String: String] = [
    "text": text, "from": miaKey,
    "sig": try! signer.signature(for: input).base64EncodedString(),
  ]
  let sealed = try! AES.GCM.seal(
    try! JSONSerialization.data(withJSONObject: body),
    using: SymmetricKey(data: Data(base64Encoded: key)!)
  ).combined!
  return sealed.base64EncodedString().replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

let shown = book([other, key]).open(direct)
precondition(
  shown == .init(chat: "s1", title: "Alice", text: "Привет\nhow are you?"),
  "the pinned preview opens with its chat's key: \(String(describing: shown))")
precondition(book([other]).open(direct) == nil, "another chat's key opens nothing")
precondition(
  book([key]).open(String(direct.dropLast(4)) + "AAAA") == nil, "a changed preview opens nothing")
precondition(PreviewBook(json: Data("not json".utf8)) == nil, "unreadable chats are none")
let written: [[String: Any]] = [["session": "s1", "name": "Alice", "keys": [key]]]
precondition(
  PreviewBook(json: try! JSONSerialization.data(withJSONObject: written))?.open(direct)?.chat
    == "s1", "a list an older build wrote still opens")

let members = [["key": miaKey, "name": "Мия"]]
let signed = book([key], members: members).open(group)
precondition(
  signed == .init(chat: "group-1", title: "Hikes", text: "Мия: Привет\nhow are you?"),
  "the pinned group preview shows its author: \(String(describing: signed))")
precondition(
  book([key], members: [["key": stranger.publicKey.rawRepresentation.base64EncodedString(), "name": "Мия"]])
    .open(group) == nil, "a preview from someone not in the group shows nothing")
precondition(book([key], members: members).open(forged(by: stranger)) == nil, "a forged signature shows nothing")
precondition(book([key], members: members).open(forged(by: mia)) != nil, "the forgery test signs as Mia would")
precondition(book([key], members: members).open(direct) == nil, "an unsigned preview in a group shows nothing")
print("notification previews: ok")
