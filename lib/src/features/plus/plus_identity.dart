import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

/// The identity a sender's badge is looked up by in a group or a channel,
/// where a message label needs a native-verified origin before it can use a
/// peer's badge. A DM names no sender beside its messages: its peer is
/// authenticated by the session and badged in the header.
String? verifiedMessagePlusIdentity(
    ConversationMessage message, String? context) {
  if (context == null) return null;
  if (message.metadata?.origin == null) return null;
  final fingerprint = message.fromFingerprint;
  return fingerprint == null ? context : '$context:$fingerprint';
}
