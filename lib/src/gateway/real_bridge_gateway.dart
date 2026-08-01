// S5: the slice-one moment-of-truth backend (ADR 0013 close-out).
//
// RealBridgeGateway delegates every Gateway method to the corresponding
// flutter_rust_bridge-generated free function in `lib/src/rust/api/`. It is
// a thin pass-through: no caching, no logic, no shaping -- the same surface
// FakeGateway mocked, now backed by the real `mosh_core` runtime. Widgets
// keep consuming `Gateway` via `gatewayProvider`; this class only exists to
// be swapped in as the default by the provider's `MOSH_FAKE_GATEWAY` flag.
//
// Lifecycle note: every method assumes `RustLib.init()` has run (main.dart
// calls it on startup; the integration test calls it explicitly). Calling
// before init throws via the frb generated `RustLib.instance.api` indirection
// -- which is exactly the behaviour the Fake could not reproduce.

import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
// diagnostics.dart defines both the AppDiagnostics/NativeRuntimeStatus types
// and the appDiagnostics()/nativeRuntimeStatus() free functions. The function
// names collide with this class's own method names, so import the functions
// under the `api` prefix while pulling the types in unqualified.
import 'package:mosh/src/rust/api/diagnostics.dart' show AppDiagnostics, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/diagnostics.dart' as api show appDiagnostics, nativeRuntimeStatus;
// private_dm.dart defines only free functions (no types); prefix them so
// they don't shadow the interface method names.
import 'package:mosh/src/rust/api/private_dm.dart' as api show acceptInvite, cancelAttachment, closeSession, createInvite, downloadAttachment, listSessions, pollSession, sendMessage;
// channel.dart and private_group.dart each define a `poll` and a `list` free
// function, and each also defines a `send` free function (plus channel `leave`
// and group `close`), so the two imports MUST use distinct prefixes to avoid
// collision; the snapshot/result types come in unqualified from their
// *_runtime.dart modules.
import 'package:mosh/src/rust/api/channel.dart' as channel_api show join, poll, list, send, leave;
import 'package:mosh/src/rust/api/private_group.dart' as group_api show createGroup, joinGroup, poll, list, send, close;
import 'package:mosh/src/rust/api/org.dart' as org_api show joinOrg;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/org_runtime.dart';

/// Real `mosh_core`-backed Gateway. See file doc for the lifecycle contract.
class RealBridgeGateway implements Gateway {
  @override
  Future<AppDiagnostics> appDiagnostics() => api.appDiagnostics();

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() =>
      api.nativeRuntimeStatus();

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) =>
      api.createInvite(request: request);

  @override
  Future<SessionSnapshot> acceptInvite({required AcceptInviteRequest request}) =>
      api.acceptInvite(request: request);

  @override
  Future<SendMessageResult> sendMessage({
    required String sessionId,
    required String body,
  }) => api.sendMessage(sessionId: sessionId, body: body);

  @override
  Future<SessionSnapshot> pollSession({required String sessionId}) =>
      api.pollSession(sessionId: sessionId);

  @override
  Future<SessionListSnapshot> listSessions() => api.listSessions();

  @override
  Future<CloseSessionResult> closeSession({required String sessionId}) =>
      api.closeSession(sessionId: sessionId);

  // Attachment transfer control delegates straight to the frb free
  // functions; both return Future<void> so no `await` is needed.
  @override
  Future<void> downloadAttachment({
    required String sessionId,
    required String attachmentId,
  }) => api.downloadAttachment(sessionId: sessionId, attachmentId: attachmentId);

  @override
  Future<void> cancelAttachment({
    required String sessionId,
    required String attachmentId,
  }) => api.cancelAttachment(sessionId: sessionId, attachmentId: attachmentId);

  // Channels/groups read seam delegates straight to the frb free functions.
  // channel_api / group_api keep the colliding `poll`/`list` names apart.
  @override
  Future<ChannelSnapshot> pollChannel({required String name}) =>
      channel_api.poll(name: name);

  @override
  Future<ChannelListSnapshot> listChannels() => channel_api.list();

  @override
  Future<GroupSnapshot> pollGroup({required String groupId}) =>
      group_api.poll(groupId: groupId);

  @override
  Future<GroupListSnapshot> listGroups() => group_api.list();

  // Channels/groups write seam delegates straight to the frb free functions.
  // The two `send` calls are disambiguated by the channel_api/group_api
  // prefixes; channel teardown is `leave`, group teardown is `close`.
  // The `joinChannel` seam (slice-3) delegates to channel_api.join; the
  // request carries name + displayName + listenPort + staticPeer (the same
  // fields InviteFlowState already sources for createInvite, ADR 0010).
  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      channel_api.join(request: request);

  @override
  Future<ChannelSendResult> sendChannel({required String name, required String body}) =>
      channel_api.send(name: name, body: body);

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) =>
      channel_api.leave(name: name);

  @override
  Future<GroupSendResult> sendGroup({required String groupId, required String body}) =>
      group_api.send(groupId: groupId, body: body);

  @override
  Future<GroupLeaveResult> closeGroup({required String groupId}) =>
      group_api.close(groupId: groupId);
  // The `createGroup` seam (slice-3) delegates to group_api.createGroup; the
  // request carries label? + displayName + listenPort + staticPeer? +
  // orgPubkey? (standalone group -- the org-bound variant in org.dart is a
  // different frb function the onboarding Group tile does not use).
  @override
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) =>
      group_api.createGroup(request: request);
  // The `joinGroup` seam (slice-3) delegates to group_api.joinGroup; the
  // request carries inviteUri + displayName + listenPort + staticPeer? +
  // orgPubkey? (null for direct paste/deep-link join; only set when the
  // invite arrived as an org group-offer).
  @override
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request}) =>
      group_api.joinGroup(request: request);
  // The `joinOrg` seam (slice-3) delegates to org_api.joinOrg; the request
  // carries bundleUri + displayName + listenPort + staticPeer? (a
  // `mosh://org` bundle URI, not an invite URI -- org joins use a different
  // field name than group joins).
  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) =>
      org_api.joinOrg(request: request);
}
