// Group orchestration state -- the Riverpod Notifier owning the group
// screen's BUSINESS state (send/retry/attachment/voice/leave/peer-DM/
// org-invite methods), extracted from `group_screen.dart`.
//
// AGENTS.md state separation: the controller owns `sending` / `offerBusy` /
// `offeredFingerprints` / `chatError` / `pendingOpen` / `_lastFailedSend`
// and does the gateway + invalidation work; the screen keeps ONLY UI state
// (`_composer` / `_showPeerStatus` / `_mobileSearchOpen` / `_search` /
// `_filter`) + navigation + the composer-clear-on-success (the controller
// returns the sent body, the screen clears `_composer` iff it still equals
// it -- React parity).
//
// The controller reads the SAME providers the screen read before
// (`gatewayProvider`, `groupSnapshotProvider(groupId)`,
// `sessionListProvider`, `orgsProvider`, `inviteFlowProvider`,
// `invitingGroupsProvider`, `offeredGroupInvitesProvider`), so the existing
// fake-gateway test overrides still apply unchanged. Its [build] does NOT
// read the gateway (only the methods do), so render-only tests that do not
// override `gatewayProvider` stay green.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert' show base64Encode;

import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/attachment_media_src.dart'
    show
        resolveMediaOpen,
        localFileSrc,
        resolveLocalAttachmentOpen,
        isViewableMedia;
import 'package:mosh/src/features/shared/attachment_open.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show
        AttachmentView,
        AttachmentDescriptor,
        AttachmentState,
        StartSessionRequest;
import 'package:mosh/src/state/channel_group_providers.dart'
    show groupSnapshotProvider;
import 'package:mosh/src/state/gateway_provider.dart' show gatewayProvider;
import 'package:mosh/src/state/session_providers.dart'
    show inviteFlowProvider, sessionListProvider;
import 'package:mosh/src/state/org_providers.dart'
    show
        OrgAddPrompt,
        orgsProvider,
        invitingGroupsProvider,
        offeredGroupInvitesProvider;

import 'package:mosh/src/features/group/group_message_list_view.dart'
    show GroupAttachmentCallbacks;
import 'package:mosh/src/features/group/group_attachment_open.dart';

/// Immutable business state for [GroupController]. Mirrors
/// [ChannelControllerState] 1-1 (the group has the same send/retry/attachment/
/// voice/peer-DM/open-attachment surface). The screen watches this via
/// `ref.watch(groupControllerProvider(groupId))` and threads the fields into
/// [GroupScreenBody].
class GroupControllerState {
  const GroupControllerState({
    this.sending = false,
    this.transferOperations = 0,
    this.offerBusy = false,
    this.offeredFingerprints = const <String>{},
    this.chatError,
    this.lastFailedSend,
    this.pendingOpen,
  });

  final bool sending;
  final int transferOperations;
  final bool offerBusy;
  final Set<String> offeredFingerprints;
  final String? chatError;
  // The recorded failed send (target + body) -- 1-1 with React's
  // `lastFailedSend`. Drives canRetrySend + retryFailedSend.
  final ({AnyConversationTarget target, String body})? lastFailedSend;
  // Ephemeral pending-open descriptor (Gap 2) -- 1-1 with React's `pendingOpen`.
  final AttachmentDescriptor? pendingOpen;

  bool get transferBusy => transferOperations > 0;

  /// Whether the banner's Retry button should be active -- 1-1 with React
  /// `canRetrySend`. `active` is always this controller's target, so it
  /// reduces to a non-null `lastFailedSend` whose target matches `target`.
  bool canRetrySend(AnyConversationTarget target) =>
      lastFailedSend != null && target == lastFailedSend!.target;

  GroupControllerState copyWith({
    bool? sending,
    int? transferOperations,
    bool? offerBusy,
    Set<String>? offeredFingerprints,
    Object? chatError = _sentinel,
    Object? lastFailedSend = _sentinel,
    Object? pendingOpen = _sentinel,
  }) => GroupControllerState(
    sending: sending ?? this.sending,
    transferOperations: transferOperations ?? this.transferOperations,
    offerBusy: offerBusy ?? this.offerBusy,
    offeredFingerprints: offeredFingerprints ?? this.offeredFingerprints,
    chatError: identical(chatError, _sentinel)
        ? this.chatError
        : chatError as String?,
    lastFailedSend: identical(lastFailedSend, _sentinel)
        ? this.lastFailedSend
        : lastFailedSend as ({AnyConversationTarget target, String body})?,
    pendingOpen: identical(pendingOpen, _sentinel)
        ? this.pendingOpen
        : pendingOpen as AttachmentDescriptor?,
  );

  static const _sentinel = Object();
}

/// Outcome of [GroupController.sendBody] / [retryFailedSend] -- the screen
/// uses `sent` + `body` to do the React-parity composer clear (clear iff the
/// composer still equals `body`).
class GroupSendOutcome {
  const GroupSendOutcome({required this.sent, required this.body});
  final bool sent;
  final String body;
}

/// Result of [GroupController.leave] -- the controller does the gateway close
/// + invalidation + clears the failed-send state; the screen navigates to
/// `/sessions` after this returns (the controller never navigates).
class GroupLeaveResult {
  const GroupLeaveResult();
}

/// Result of [GroupController.onPeerMessage] -- `sessionId` is non-null on a
/// successful DM-offer send (the screen navigates to `/dm/<id>`); null when
/// the peer was already offered (no-op).
class GroupPeerDmResult {
  const GroupPeerDmResult(this.sessionId);
  final String? sessionId;
  static const noop = GroupPeerDmResult(null);
}

/// Family by group id. Riverpod v3 passes the family arg to the Notifier's
/// constructor, so the class extends plain `Notifier` and stores the arg in a
/// field (mirrors `voiceCallOrchestratorProvider`).
final groupControllerProvider =
    NotifierProvider.family<GroupController, GroupControllerState, String>(
      GroupController.new,
    );

/// Owns the group screen's business state + orchestration methods. Mirrors
/// [ChannelController] 1-1 on the shared surface; the group-specific addition
/// is [inviteMembers] (the org one-click add). The controller never
/// navigates and never touches the composer.
class GroupController extends Notifier<GroupControllerState> {
  GroupController(this.groupId);

  /// The group id (the family arg) -- the conversation identity.
  final String groupId;

  /// This group as a Gateway target. Every send, retry, attachment and
  /// leave call passes it, so the kind is named once here.
  late final GroupTarget _target = GroupTarget(groupId);

  @override
  GroupControllerState build() => const GroupControllerState();

  AnyConversationTarget get target => _target;

  Future<T> _runTransfer<T>(Future<T> Function() operation) async {
    state = state.copyWith(transferOperations: state.transferOperations + 1);
    try {
      return await operation();
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          transferOperations: state.transferOperations > 0
              ? state.transferOperations - 1
              : 0,
        );
      }
    }
  }

  /// Sends a body verbatim -- 1-1 with React `sendMessageBody`, the group
  /// branch. On SUCCESS clears `lastFailedSend` + `chatError` and invalidates
  /// the group snapshot; on FAILURE records `lastFailedSend` + `chatError`.
  /// Returns [GroupSendOutcome] so the screen does the React-parity composer
  /// clear. The screen calls this from its `onSend` after reading
  /// `_composer.text` (the composer is UI state the controller never touches).
  Future<GroupSendOutcome> sendBody(String body) async {
    if (body.isEmpty || state.sending) {
      return const GroupSendOutcome(sent: false, body: '');
    }
    state = state.copyWith(sending: true, chatError: null);
    try {
      await ref.read(gatewayProvider).send(_target, body: body);
      state = state.copyWith(lastFailedSend: null, chatError: null);
      ref.invalidate(groupSnapshotProvider(groupId));
      return GroupSendOutcome(sent: true, body: body);
    } catch (e) {
      state = state.copyWith(
        lastFailedSend: (target: _target, body: body),
        chatError: e.toString(),
      );
      return GroupSendOutcome(sent: false, body: body);
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Re-sends the last failed body -- 1-1 with React `retryFailedSend`: no-op
  /// if there is no recorded failure for the active target; otherwise re-run
  /// [sendBody] with the stored body. Returns the outcome so the screen
  /// clears the composer on a successful retry (React parity -- the banner's
  /// onRetry path).
  Future<GroupSendOutcome> retryFailedSend() async {
    final failed = state.lastFailedSend;
    if (failed == null || _target != failed.target) {
      return const GroupSendOutcome(sent: false, body: '');
    }
    return sendBody(failed.body);
  }

  // Slice-3 attachment SEND -- 1-1 with React's `sendAttachment`, the group
  // branch: read the picked file's bytes (already base64-encoded by
  // AttachmentPicker), call the Gateway group send seam, then invalidate the
  // group snapshot so the next poll renders the new row. `thumbnailBase64`/
  // `voice` stay null for this atomic. The 50 MB ceiling is enforced in the
  // picker BEFORE bytes are read.
  Future<void> sendAttachment(PickedAttachment attachment) async {
    if (state.sending) return;
    state = state.copyWith(sending: true);
    try {
      await _runTransfer(
        () => ref.read(gatewayProvider).sendAttachment(
          _target,
          fileName: attachment.fileName,
          mime: attachment.mime,
          dataBase64: attachment.dataBase64,
          thumbnailBase64: attachment.thumbnailBase64,
        ),
      );
      ref.invalidate(groupSnapshotProvider(groupId));
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Group voice SEND -- 1-1 with React `sendVoice`, the group branch. Reads
  /// the recorded file (path from the VoiceComposer), base64-encodes the
  /// bytes, derives `voice-message.<ext>` from the mime, and calls the
  /// Gateway group send seam with `voice: VoiceMeta(durationMs, peaksBase64)`.
  Future<void> sendVoice(VoiceSend voice) async {
    if (state.sending) return;
    state = state.copyWith(sending: true);
    try {
      await _runTransfer(() async {
        final file = File(voice.path);
        final bytes = await file.readAsBytes();
        final ext = voice.mime.contains('mp4') ? 'm4a' : 'webm';
        final fileName = 'voice-message.$ext';
        await ref.read(gatewayProvider).sendAttachment(
          _target,
          fileName: fileName,
          mime: voice.mime,
          dataBase64: base64Encode(bytes),
          voice: VoiceMeta(
            durationMs: voice.durationMs,
            peaksB64: voice.peaksBase64,
          ),
        );
      });
      ref.invalidate(groupSnapshotProvider(groupId));
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Builds the per-row transfer-action callbacks for the group message
  /// row's AttachmentCard: download/cancel fire the Gateway seam then
  /// invalidate the group snapshot (fire-and-forget via `unawaited`).
  /// `onOpen` delegates back to the screen's open handler (passed in) so the
  /// screen wires the viewer + the controller's pending-open arming.
  GroupAttachmentCallbacks Function(AttachmentView? view) attachmentCallbacks(
    void Function(AttachmentDescriptor descriptor, AttachmentView? view) onOpen,
  ) =>
      (view) => GroupAttachmentCallbacks(
        busy: state.transferBusy,
        onDownload: (id) => unawaited(
          _runTransfer(
            () => ref
                .read(gatewayProvider)
                .downloadAttachment(_target, attachmentId: id)
                .then((_) => ref.invalidate(groupSnapshotProvider(groupId))),
          ),
        ),
        onCancel: (id) => unawaited(
          _runTransfer(
            () => ref
                .read(gatewayProvider)
                .cancelAttachment(_target, attachmentId: id)
                .then((_) => ref.invalidate(groupSnapshotProvider(groupId))),
          ),
        ),
        onOpen: (descriptor) => onOpen(descriptor, view),
      );

  /// Retry a failed outbound message (React `retryGroupMessage`). Fire-and-
  /// forget via `unawaited`, then invalidate the group snapshot so the next
  /// poll re-renders the row's delivery status.
  void retryMessage(String messageId) {
    unawaited(
      ref
          .read(gatewayProvider)
          .retry(_target, messageId: messageId)
          .then((_) => ref.invalidate(groupSnapshotProvider(groupId))),
    );
  }

  /// Opens an attachment -- 1-1 with React `openAttachment`. The decision
  /// (src / download / wait) comes from [resolveMediaOpen] (the pure port of
  /// the React state machine). The controller arms `pendingOpen` + kicks the
  /// download (business state + gateway), then returns an immutable intent for
  /// the screen to interpret.
  AttachmentOpenIntent openAttachment(
    AttachmentDescriptor descriptor,
    AttachmentView? view,
  ) {
    final localIntent = resolveLocalAttachmentOpen(
      descriptor: descriptor,
      view: view,
    );
    if (localIntent is! AttachmentNoopOpenIntent) return localIntent;
    if (!isViewableMedia(descriptor.mime)) {
      return const AttachmentNoopOpenIntent();
    }
    final decision = resolveMediaOpen(
      descriptor: descriptor,
      view: view,
      kind: 'group',
      host: groupId,
    );
    if (decision.wait) {
      state = state.copyWith(pendingOpen: descriptor);
    }
    if (decision.download) {
      unawaited(
        _runTransfer(
          () => ref
              .read(gatewayProvider)
              .downloadAttachment(_target,
                  attachmentId: descriptor.attachmentId)
              .then((_) => ref.invalidate(groupSnapshotProvider(groupId))),
        ),
      );
    }
    if (decision.src != null) {
      return AttachmentMediaOpenIntent(
        descriptor: descriptor,
        src: decision.src!,
      );
    }
    return const AttachmentNoopOpenIntent();
  }

  /// Resolves `pendingOpen` against an updated attachments list -- 1-1 with
  /// React's `useEffect`. Pure with respect to the snapshot; the side effects
  /// are: clear `pendingOpen` in state (business) + return
  /// [GroupPendingResolution] so the screen shows the viewer (UI) or drops
  /// the pending. Driven by the screen's `ref.listen` on the group snapshot.
  GroupPendingResolution resolvePendingOpen(List<AttachmentView> attachments) {
    final pending = state.pendingOpen;
    if (pending == null) return const GroupPendingResolution.none();
    AttachmentView? view;
    for (final v in attachments) {
      if (v.attachmentId == pending.attachmentId) {
        view = v;
        break;
      }
    }
    if (view == null) return const GroupPendingResolution.none();
    final localPath = view.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      state = state.copyWith(pendingOpen: null);
      return GroupPendingResolution.show(pending, localFileSrc(localPath));
    }
    if (view.state == AttachmentState.failed ||
        view.state == AttachmentState.cancelled) {
      state = state.copyWith(pendingOpen: null);
      return const GroupPendingResolution.drop();
    }
    return const GroupPendingResolution.none();
  }

  /// Start a 1:1 DM with a group peer -- 1-1 with React `offerDm`, the group
  /// branch: create a private DM invite (`gateway.createInvite` with the
  /// `requestBase` from [inviteFlowProvider]), send the offer over this
  /// group (`gateway.sendGroupDmOffer`), track the peer fingerprint as
  /// offered, and invalidate `sessionListProvider`. Returns
  /// [GroupPeerDmResult] carrying the new session id so the screen navigates
  /// to `/dm/<id>` (the controller never navigates). No-op (returns `noop`)
  /// if the peer was already offered.
  Future<GroupPeerDmResult> onPeerMessage(String peerFingerprint) async {
    if (state.offeredFingerprints.contains(peerFingerprint)) {
      return GroupPeerDmResult.noop;
    }
    state = state.copyWith(offerBusy: true);
    try {
      final flow = ref.read(inviteFlowProvider);
      final invite = await ref
          .read(gatewayProvider)
          .createInvite(
            request: StartSessionRequest(
              displayName: flow.displayName,
              listenPort: flow.listenPort,
              staticPeer: flow.staticPeer,
            ),
          );
      await ref
          .read(gatewayProvider)
          .sendGroupDmOffer(
            groupId: groupId,
            peerFingerprint: peerFingerprint,
            inviteUri: invite.inviteUri,
          );
      final offered = {...state.offeredFingerprints, peerFingerprint};
      state = state.copyWith(offeredFingerprints: offered);
      ref.invalidate(sessionListProvider);
      return GroupPeerDmResult(invite.sessionId);
    } finally {
      state = state.copyWith(offerBusy: false);
    }
  }

  /// Org admin one-click add (React `inviteMembersToGroup`, use-orgs.ts
  /// L197-205). Calls the Gateway org-group-invite seam with the missing
  /// roster peer-ids, marks them offered so the banner does not re-count
  /// them, toggles the busy flag, and refreshes orgs + the group snapshot so
  /// the next render re-evaluates the prompt. Fire-and-forget via
  /// `unawaited` (the busy flag + invalidation drive the UI). No navigation.
  void inviteMembers(OrgAddPrompt prompt) {
    final peerIds = prompt.missingPeerIds;
    if (peerIds.isEmpty) return;
    ref.read(invitingGroupsProvider.notifier).start(groupId);
    unawaited(
      ref
          .read(gatewayProvider)
          .orgGroupInviteMembers(
            orgPubkey: prompt.orgPubkey,
            groupId: groupId,
            memberPeerIds: peerIds,
          )
          .then((_) {
            ref
                .read(offeredGroupInvitesProvider.notifier)
                .markInvited(groupId, peerIds);
          })
          .catchError((_) {})
          .whenComplete(() {
            ref.read(invitingGroupsProvider.notifier).finish(groupId);
            ref.invalidate(orgsProvider);
            ref.invalidate(groupSnapshotProvider(groupId));
          }),
    );
  }

  /// Leaves the group -- the gateway close + invalidation + failed-send
  /// clear half of the screen's former `_leave` (React `clearFailedSend` +
  /// `closeChatTarget`). Returns [GroupLeaveResult] so
  /// the screen navigates to `/sessions` (the controller never navigates).
  ///
  /// The active-conversation-key clear + navigation stay in the screen (the
  /// screen owns the active-conversation lifecycle + navigation); this
  /// method does only the gateway close + invalidation + failed-send clear.
  Future<GroupLeaveResult> leave() async {
    state = state.copyWith(lastFailedSend: null, chatError: null);
    await ref.read(gatewayProvider).leave(_target);
    ref.invalidate(groupSnapshotProvider(groupId));
    return const GroupLeaveResult();
  }
}
