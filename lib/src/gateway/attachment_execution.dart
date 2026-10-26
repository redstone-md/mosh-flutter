import 'package:mosh/src/rust/api/conversation.dart';

/// Admits user transfers before the Android OS execution request.
abstract interface class AttachmentExecution {
  Future<void> send(
      BridgeConversationRef target, BridgeAttachmentPayload payload);
  Future<void> download(BridgeConversationRef target, String attachmentId);
}
