import Foundation
import Security

/// What the wake service needs kept on this phone, in the Keychain group
/// the app shares with its notification extension (the first of
/// `keychain-access-groups`, so items land there without naming it), and
/// readable while the phone is locked after its first unlock, when a push
/// starts the app or the extension. A Keychain call can wait on securityd
/// for seconds, so the app makes them in order on `queue`, never on the
/// main thread.
enum WakeKeychain {
  enum Item: String {
    /// The wake registration: handle and secret.
    case registration
    /// The chats the extension opens previews for, as the app wrote them
    /// (lib/src/features/wake/wake_previews.dart).
    case previews
  }

  static let queue = DispatchQueue(label: "app.mosh.wake-keychain")

  private static func query(_ item: Item) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.mosh.wake",
      kSecAttrAccount as String: item.rawValue,
    ]
  }

  static func load(_ item: Item) -> String? {
    var found = query(item)
    found[kSecReturnData as String] = true
    var value: CFTypeRef?
    guard SecItemCopyMatching(found as CFDictionary, &value) == errSecSuccess,
      let data = value as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ value: String, as item: Item) -> OSStatus {
    SecItemDelete(query(item) as CFDictionary)
    var added = query(item)
    added[kSecValueData as String] = Data(value.utf8)
    added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(added as CFDictionary, nil)
  }
}
