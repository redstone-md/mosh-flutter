import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

/// Legacy public messages can claim someone else's fingerprint. Only native
/// verified origins may be associated with authenticated PLUS advertisements.
String? verifiedMessagePlusIdentity(
    ConversationMessage message, String? context) {
  if (context == null || message.metadata?.origin == null) return null;
  final fingerprint = message.fromFingerprint;
  return fingerprint == null ? context : '$context:$fingerprint';
}
