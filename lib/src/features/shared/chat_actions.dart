// chat_actions -- the shared DM/channel/group send/retry/attachment/leave
// dispatch, 1-1 with React chat-actions.ts (mosh/src/features/private-dm/
// chat-actions.ts). A sealed [ChatTarget] union (dm | channel | group)
// routes each action to the right Gateway method so the three conversation
// screens delegate here instead of triplicating the orchestration. Pure
// behavior-preserving extraction (Gap 4); the failed-send retry queue +
// ChatError banner (Gaps 1+3) land on top of this.
//
// Gateway method names verified against lib/src/gateway/gateway.dart -- the
// Dart frb-generated Gateway differs from React's native-messaging-gateway
// in three places: DM text send is `sendMessage` (not `sendPrivateMessage`),
// DM download/cancel are `downloadAttachment`/`cancelAttachment` (not
// `downloadPrivateAttachment`/`cancelPrivateAttachment`), and the group
// close is `closeGroup` (not `closePrivateGroup`). Named params also
// differ: the channel id is `name` and the group id is `groupId` (React
// used `id`).
library;

import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;

/// The conversation kind a chat action targets -- 1-1 with React's
/// `ChatTarget` union (dm | channel | group). The `id` mirrors React
/// `target.id` (a DM session id, a channel name, or a group id).
sealed class ChatTarget {
  const ChatTarget();

  /// The session id (DM), channel name, or group id -- React `target.id`.
  String get id;
}

/// A private DM session -- React `ChatTarget.type === "dm"`. Routes text
/// send to `Gateway.sendMessage`, retry to `retryDmMessage`, attachment
/// send to `sendPrivateAttachment`, download/cancel to
/// `downloadAttachment`/`cancelAttachment`, close to `closeSession`.
class DmTarget extends ChatTarget {
  const DmTarget(this.id);
  @override
  final String id;
}

/// A public channel -- React `ChatTarget.type === "channel"`. The `id` is
/// the channel name (Gateway keys channel methods on `name:`). Routes text
/// send to `Gateway.sendChannel`, retry to `retryChannelMessage`, attachment
/// send to `sendChannelAttachment`, download/cancel to
/// `downloadChannelAttachment`/`cancelChannelAttachment`, close to
/// `leaveChannel`.
class ChannelTarget extends ChatTarget {
  const ChannelTarget(this.id);
  @override
  final String id;
}

/// A private group -- React `ChatTarget.type === "group"`. The `id` is the
/// group id (Gateway keys group methods on `groupId:`). Routes text send to
/// `Gateway.sendGroup`, retry to `retryGroupMessage`, attachment send to
/// `sendGroupAttachment`, download/cancel to
/// `downloadGroupAttachment`/`cancelGroupAttachment`, close to `closeGroup`.
class GroupTarget extends ChatTarget {
  const GroupTarget(this.id);
  @override
  final String id;
}

/// Sends a text message -- 1-1 with React `sendChatText`. Dispatches to
/// `sendMessage` (DM) / `sendChannel` / `sendGroup` based on [target]. The
/// gateway's send result is discarded (mirrors React's `Promise<void>`);
/// the screen's `ref.invalidate(provider)` after the `await` re-fetches the
/// snapshot so the next poll re-renders the new row.
Future<void> sendChatText({
  required Gateway gateway,
  required ChatTarget target,
  required String body,
}) {
  return switch (target) {
    DmTarget(:final id) => gateway.sendMessage(sessionId: id, body: body),
    ChannelTarget(:final id) => gateway.sendChannel(name: id, body: body),
    GroupTarget(:final id) => gateway.sendGroup(groupId: id, body: body),
  };
}

/// Retries a server-side failed+retryable message by id -- 1-1 with React
/// `retryChatMessage`. Dispatches to `retryDmMessage` / `retryChannelMessage`
/// / `retryGroupMessage`. The gateway's send result is discarded (React
/// `Promise<void>`); the screen invalidates after the `await`.
Future<void> retryChatMessage({
  required Gateway gateway,
  required ChatTarget target,
  required String messageId,
}) {
  return switch (target) {
    DmTarget(:final id) =>
      gateway.retryDmMessage(sessionId: id, messageId: messageId),
    ChannelTarget(:final id) =>
      gateway.retryChannelMessage(name: id, messageId: messageId),
    GroupTarget(:final id) =>
      gateway.retryGroupMessage(groupId: id, messageId: messageId),
  };
}

/// Sends an attachment -- 1-1 with React `sendChatAttachment`. Dispatches
/// to `sendPrivateAttachment` / `sendChannelAttachment` /
/// `sendGroupAttachment` with the base64 payload + optional thumbnail /
/// voice metadata. The gateway's `AttachmentSendResult` is discarded
/// (React `Promise<void>`); the screen invalidates after the `await`.
Future<void> sendChatAttachment({
  required Gateway gateway,
  required ChatTarget target,
  required String fileName,
  required String mime,
  required String dataBase64,
  String? thumbnailBase64,
  VoiceMeta? voice,
}) {
  return switch (target) {
    DmTarget(:final id) => gateway.sendPrivateAttachment(
        sessionId: id,
        fileName: fileName,
        mime: mime,
        dataBase64: dataBase64,
        thumbnailBase64: thumbnailBase64,
        voice: voice,
      ),
    ChannelTarget(:final id) => gateway.sendChannelAttachment(
        name: id,
        fileName: fileName,
        mime: mime,
        dataBase64: dataBase64,
        thumbnailBase64: thumbnailBase64,
        voice: voice,
      ),
    GroupTarget(:final id) => gateway.sendGroupAttachment(
        groupId: id,
        fileName: fileName,
        mime: mime,
        dataBase64: dataBase64,
        thumbnailBase64: thumbnailBase64,
        voice: voice,
      ),
  };
}

/// Downloads an attachment -- 1-1 with React `downloadChatAttachment`.
/// Dispatches to `downloadAttachment` (DM) / `downloadChannelAttachment` /
/// `downloadGroupAttachment`. Fire-and-forget from the caller; invalidation
/// stays in the screen.
Future<void> downloadChatAttachment({
  required Gateway gateway,
  required ChatTarget target,
  required String attachmentId,
}) {
  return switch (target) {
    DmTarget(:final id) =>
      gateway.downloadAttachment(sessionId: id, attachmentId: attachmentId),
    ChannelTarget(:final id) => gateway.downloadChannelAttachment(
        name: id,
        attachmentId: attachmentId,
      ),
    GroupTarget(:final id) =>
      gateway.downloadGroupAttachment(groupId: id, attachmentId: attachmentId),
  };
}

/// Cancels an in-flight attachment transfer -- 1-1 with React
/// `cancelChatAttachment`. Dispatches to `cancelAttachment` (DM) /
/// `cancelChannelAttachment` / `cancelGroupAttachment`.
Future<void> cancelChatAttachment({
  required Gateway gateway,
  required ChatTarget target,
  required String attachmentId,
}) {
  return switch (target) {
    DmTarget(:final id) =>
      gateway.cancelAttachment(sessionId: id, attachmentId: attachmentId),
    ChannelTarget(:final id) => gateway.cancelChannelAttachment(
        name: id,
        attachmentId: attachmentId,
      ),
    GroupTarget(:final id) =>
      gateway.cancelGroupAttachment(groupId: id, attachmentId: attachmentId),
  };
}

/// Closes the conversation -- 1-1 with React `closeChatTarget`. Dispatches
/// to `closeSession` (DM) / `leaveChannel` (channel) / `closeGroup` (group).
/// The result is discarded (React `Promise<void>`); the screen's
/// post-close invalidation + navigation stay inline.
Future<void> closeChatTarget({
  required Gateway gateway,
  required ChatTarget target,
}) {
  return switch (target) {
    DmTarget(:final id) => gateway.closeSession(sessionId: id),
    ChannelTarget(:final id) => gateway.leaveChannel(name: id),
    GroupTarget(:final id) => gateway.closeGroup(groupId: id),
  };
}

/// Same-target equality -- 1-1 with React `sameChatTarget`. Two targets
/// are the same conversation iff they are the same kind (DmTarget vs
/// ChannelTarget vs GroupTarget) AND share the same `id`. Used by Gaps 1+3
/// to decide whether a re-render is the same conversation.
bool sameChatTarget(ChatTarget a, ChatTarget b) {
  if (a.runtimeType != b.runtimeType) return false;
  return a.id == b.id;
}
