import Foundation

// Opens the preview mosh-core pins in
// the_sealed_form_is_what_the_notification_extension_opens, so a change to
// the sealed form on either side fails one of the two.
let key = Data(repeating: 7, count: 32).base64EncodedString()
let other = Data(repeating: 8, count: 32).base64EncodedString()
let pinned =
  "CQkJCQkJCQkJCQkJXKfw8caE41uCslTpZjobD2Zg1iK2spmoANlmx6cRIQO8kNjhn4iTe0muP9iBv9ClUiO7XJs"

func book(_ keys: [String]) -> PreviewBook {
  let chats = [["session": "s1", "name": "Alice", "keys": keys]]
  return PreviewBook(json: try! JSONSerialization.data(withJSONObject: chats))!
}

let shown = book([other, key]).open(pinned)
precondition(
  shown == .init(session: "s1", name: "Alice", text: "Привет\nhow are you?"),
  "the pinned preview opens with its chat's key: \(String(describing: shown))")
precondition(book([other]).open(pinned) == nil, "another chat's key opens nothing")
precondition(book([key]).open(String(pinned.dropLast(4)) + "AAAA") == nil, "a changed preview opens nothing")
precondition(PreviewBook(json: Data("not json".utf8)) == nil, "unreadable chats are none")
print("notification previews: ok")
