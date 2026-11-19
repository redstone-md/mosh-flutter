import UserNotifications

/// Turns a wake service alert ("New message") into the chat's name and the
/// text, with a group member's name before it, opened from the push's
/// sealed preview with the keys the app left in the shared Keychain. Needs
/// neither the app nor the network, so it works while Mosh is closed.
/// Anything it cannot open keeps the alert as it came.
final class NotificationService: UNNotificationServiceExtension {
  private var original: (UNNotificationContent, (UNNotificationContent) -> Void)?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    original = (request.content, contentHandler)
    guard let preview = request.content.userInfo["preview"] as? String,
      let stored = WakeKeychain.load(.previews),
      let shown = PreviewBook(json: Data(stored.utf8))?.open(preview),
      let content = request.content.mutableCopy() as? UNMutableNotificationContent
    else { return contentHandler(request.content) }
    if !shown.title.isEmpty { content.title = shown.title }
    content.body = shown.text
    content.threadIdentifier = shown.chat
    contentHandler(content)
  }

  override func serviceExtensionTimeWillExpire() {
    if let (content, handler) = original { handler(content) }
  }
}
