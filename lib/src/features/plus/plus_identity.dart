import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

/// DMs authenticate the peer through their session. Multi-party message labels
/// require a native-verified origin before they can use a peer's badge.
String? verifiedMessagePlusIdentity(
    ConversationMessage message, String? context, ConversationKind kind) {
  if (context == null) return null;
  if (kind == ConversationKind.dm) return context;
  if (message.metadata?.origin == null) return null;
  final fingerprint = message.fromFingerprint;
  return fingerprint == null ? context : '$context:$fingerprint';
}
