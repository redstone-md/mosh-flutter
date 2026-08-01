// Sealed seam between the flutter_rust_bridge surface and the Flutter UI.
//
// `FakeGateway` (S4) and `RealBridgeGateway` (S5) both implement this interface;
// widgets depend on `Gateway`, never on a concrete impl, so swapping the
// wired runtime is one provider change (ADR 0013).
//
// The eighteen methods below mirror the slice-one Rust `mosh_core::api` surface
// 1:1, poll-based (no streams). Signatures match the generated frb functions.
// The channels/groups read seam adds pollChannel/listChannels/pollGroup/
// listGroups; the channels/groups write seam adds sendChannel/leaveChannel/
// sendGroup/closeGroup. The remaining write halves of that slice (create/join/
// send attachment/dm offers/...) land in a later atomic.

import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

/// Abstraction over the slice-one private-DM + diagnostics API.
///
/// Implementations: `FakeGateway` (in-Dart, first slice only, ADR 0013) and
/// `RealBridgeGateway` (delegates to the generated frb functions, S5). Widgets
/// consume this interface, never a concrete class, so the wired backend is a
/// single Riverpod provider swap.
abstract interface class Gateway {
  Future<AppDiagnostics> appDiagnostics();
  Future<NativeRuntimeStatus> nativeRuntimeStatus();
  Future<InviteCreated> createInvite({required StartSessionRequest request});
  Future<SessionSnapshot> acceptInvite({required AcceptInviteRequest request});
  Future<SendMessageResult> sendMessage({required String sessionId, required String body});
  Future<SessionSnapshot> pollSession({required String sessionId});
  Future<SessionListSnapshot> listSessions();
  Future<CloseSessionResult> closeSession({required String sessionId});

  // Attachment transfer control (1:1 port of `download_attachment` /
  // `cancel_attachment`). Both drive the peer's inbound transfer; progress
  // surfaces in the next `pollSession` snapshot's `attachments`. The "open"
// action is client-side (opens `localPath` / streams) and has no Rust fn.
  Future<void> downloadAttachment({required String sessionId, required String attachmentId});
  Future<void> cancelAttachment({required String sessionId, required String attachmentId});

  // Channels/groups read seam (1:1 port of `channel_poll`/`channel_list`/
  // `private_group_poll`/`private_group_list`). Poll-based mirrors of the
  // React `pollChannel`/`listChannels`/`pollGroup`/`listGroups` shapes; the
  // write methods (create/join/send/close/...) land in a later atomic.
  Future<ChannelSnapshot> pollChannel({required String name});
  Future<ChannelListSnapshot> listChannels();
  Future<GroupSnapshot> pollGroup({required String groupId});
  Future<GroupListSnapshot> listGroups();

  // Channels/groups write seam (1:1 port of `channel_send`/`channel_leave`/
  // `private_group_send`/`private_group_close`). The minimal write surface a
  // chat screen needs: posting a message and closing the conversation. The
  // frb channel `leave` and group `close` both map here (channel's teardown is
  // named `leave`, group's is named `close`); create/join/attachment/dm-offer
  // write methods stay deferred to a later atomic.
  Future<ChannelSendResult> sendChannel({required String name, required String body});
  Future<ChannelLeaveResult> leaveChannel({required String name});
  Future<GroupSendResult> sendGroup({required String groupId, required String body});
  Future<GroupLeaveResult> closeGroup({required String groupId});
}
