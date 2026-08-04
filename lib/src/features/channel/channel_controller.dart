// Channel orchestration state -- the Riverpod Notifier that owns the channel
// screen's BUSINESS state + the send/retry/attachment/voice/leave/peer-DM/
// open-attachment methods. Extracted from `channel_screen.dart` so the screen
// clears the AGENTS.md 500-line ceiling (it was 568; the dominant remaining
// bulk was this ~17-method orchestration class + its business-state fields).
//
// AGENTS.md state separation (controller = business state, screen = UI state):
// the controller owns `sending` / `offerBusy` / `offeredFingerprints` /
// `chatError` / `pendingOpen` / `_lastFailedSend` and does the gateway +
// invalidation work; the screen keeps ONLY UI state (`_composer` /
// `_showPeerStatus` / `_mobileSearchOpen` / `_search` / `_filter`) +
// navigation (the controller returns results, the screen does `context.go`)
// + the composer-clear-on-success (the controller returns the sent body, the
// screen clears `_composer` iff it still equals it -- React parity).
//
// The controller NEVER navigates and NEVER touches the composer (those are
// UI concerns). Methods that can clear the composer on success
// ([sendBody] / [retryFailedSend]) return [ChannelSendOutcome] carrying the
// body + a `sent` flag; the screen does the conditional clear. [leave]
// returns [ChannelLeaveResult] (the screen navigates to /sessions).
// [onPeerMessage] returns [ChannelPeerDmResult] carrying the new session id
// (the screen navigates to /dm/<id>). [openAttachment] /
// [resolvePendingOpen] return intents ([ChannelOpenResult] /
// [ChannelPendingResolution]) so the screen owns the MediaViewer and
// platform side effects.
//
// The controller reads `gatewayProvider`, invalidates
// `channelSnapshotProvider(name)` + `sessionListProvider`, and reads
// `inviteFlowProvider` -- the SAME providers the screen read before, so the
// existing fake-gateway test overrides (which override `gatewayProvider` +
// `channelSnapshotProvider` in the ProviderScope) still apply unchanged.
// The controller's [build] does NOT read the gateway (only the methods do),
// so render-only tests that do not override `gatewayProvider` stay green
// (the gateway is never constructed for them).
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
import 'package:mosh/src/features/shared/chat_actions.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show
        AttachmentView,
        AttachmentDescriptor,
        AttachmentState,
        StartSessionRequest;
import 'package:mosh/src/state/channel_group_providers.dart'
    show channelSnapshotProvider;
import 'package:mosh/src/state/gateway_provider.dart' show gatewayProvider;
import 'package:mosh/src/state/session_providers.dart'
    show inviteFlowProvider, sessionListProvider;

import 'package:mosh/src/features/channel/channel_message_list_view.dart'
    show ChannelAttachmentCallbacks;

/// Immutable business state for [ChannelController]. The screen watches this
/// via `ref.watch(channelControllerProvider(name))` and threads the fields
/// into [ChannelScreenBody] (sending / offerBusy / offeredFingerprints /
/// chatError / canRetrySend). `pendingOpen` is owned here but resolved by
/// [ChannelController.resolvePendingOpen] (driven by the screen's
/// `ref.listen` on the channel snapshot).
class ChannelControllerState {
  const ChannelControllerState({
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
  final ({ChatTarget target, String body})? lastFailedSend;
  // Ephemeral pending-open descriptor (Gap 2) -- 1-1 with React's `pendingOpen`.
  final AttachmentDescriptor? pendingOpen;

  bool get transferBusy => transferOperations > 0;

  /// Whether the banner's Retry button should be active -- 1-1 with React
  /// `canRetrySend`. `active` is always this controller's target, so it
  /// reduces to a non-null `lastFailedSend` whose target matches `target`.
  bool canRetrySend(ChatTarget target) =>
      lastFailedSend != null && sameChatTarget(target, lastFailedSend!.target);

  ChannelControllerState copyWith({
    bool? sending,
    int? transferOperations,
    bool? offerBusy,
    Set<String>? offeredFingerprints,
    Object? chatError = _sentinel,
    Object? lastFailedSend = _sentinel,
    Object? pendingOpen = _sentinel,
  }) =>
      ChannelControllerState(
        sending: sending ?? this.sending,
        transferOperations: transferOperations ?? this.transferOperations,
        offerBusy: offerBusy ?? this.offerBusy,
        offeredFingerprints: offeredFingerprints ?? this.offeredFingerprints,
        chatError: identical(chatError, _sentinel)
            ? this.chatError
            : chatError as String?,
        lastFailedSend: identical(lastFailedSend, _sentinel)
            ? this.lastFailedSend
            : lastFailedSend as ({ChatTarget target, String body})?,
        pendingOpen: identical(pendingOpen, _sentinel)
            ? this.pendingOpen
            : pendingOpen as AttachmentDescriptor?,
      );

  static const _sentinel = Object();
}

/// Outcome of [ChannelController.sendBody] / [retryFailedSend] -- the screen
/// uses `sent` + `body` to do the React-parity composer clear (clear iff the
/// composer still equals `body`). `sent == false` means the send threw (the
/// controller already recorded the failure in `chatError` +
/// `lastFailedSend`) or there was nothing to send/retry.
class ChannelSendOutcome {
  const ChannelSendOutcome({required this.sent, required this.body});
  final bool sent;
  final String body;
}

/// Result of [ChannelController.leave] -- the controller does the gateway
/// close + invalidation + clears the failed-send state; the screen navigates
/// to `/sessions` after this returns (the controller never navigates).
class ChannelLeaveResult {
  const ChannelLeaveResult();
}

/// Result of [ChannelController.onPeerMessage] -- `sessionId` is non-null on
/// a successful DM-offer send (the screen navigates to `/dm/<id>`); null when
/// the peer was already offered (no-op) -- the screen does nothing.
class ChannelPeerDmResult {
  const ChannelPeerDmResult(this.sessionId);
  final String? sessionId;
  static const noop = ChannelPeerDmResult(null);
}

/// Result of [ChannelController.resolvePendingOpen] -- the controller clears
/// `pendingOpen` internally on `show`/`drop`; `show` carries the descriptor +
/// local src so the screen opens the viewer, `drop` means the transfer
/// failed/cancelled (nothing to show), `none` means there was no pending open
/// or the matching view is not ready yet.
sealed class ChannelPendingResolution {
  const ChannelPendingResolution();
  const factory ChannelPendingResolution.show(
      AttachmentDescriptor descriptor, String src) = ChannelPendingShow;
  const factory ChannelPendingResolution.drop() = ChannelPendingDrop;
  const factory ChannelPendingResolution.none() = ChannelPendingNone;
}

class ChannelPendingShow extends ChannelPendingResolution {
  const ChannelPendingShow(this.descriptor, this.src);
  final AttachmentDescriptor descriptor;
  final String src;
}

class ChannelPendingDrop extends ChannelPendingResolution {
  const ChannelPendingDrop();
}

class ChannelPendingNone extends ChannelPendingResolution {
  const ChannelPendingNone();
}

/// Family by channel name. Riverpod v3 passes the family arg to the Notifier's
/// constructor, so the class extends plain `Notifier` and stores the arg in a
/// field (mirrors `voiceCallOrchestratorProvider`).
final channelControllerProvider =
    NotifierProvider.family<ChannelController, ChannelControllerState, String>(
        ChannelController.new);

/// Owns the channel screen's business state + orchestration methods. See the
/// library doc for the controller/screen split. The controller never
/// navigates and never touches the composer; it returns results the screen
/// acts on.
class ChannelController extends Notifier<ChannelControllerState> {
  ChannelController(this.name);

  /// The channel name (the family arg) -- the conversation identity.
  final String name;

  /// The sealed [ChatTarget] for this channel -- routes send/retry/attachment/
  /// leave dispatch through `chat_actions.dart` (the shared DM/channel/group
  /// seam, Gap 4) so the gateway method name is decided once here.
  late final ChatTarget _target = ChannelTarget(name);

  @override
  ChannelControllerState build() => const ChannelControllerState();

  ChatTarget get target => _target;

  Future<T> _runTransfer<T>(Future<T> Function() operation) async {
    state = state.copyWith(transferOperations: state.transferOperations + 1);
    try {
      return await operation();
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          transferOperations:
              state.transferOperations > 0 ? state.transferOperations - 1 : 0,
        );
      }
    }
  }

  /// Sends a body verbatim -- 1-1 with React `sendMessageBody`. Runs the full
  /// try/catch/finally: on SUCCESS clears `lastFailedSend` + `chatError`
  /// (React `setLastFailedSend(null)` + `onError(undefined)`) and invalidates
  /// the channel snapshot; on FAILURE records `lastFailedSend` + `chatError`.
  /// Returns [ChannelSendOutcome] so the screen does the React-parity
  /// composer clear (clear iff the composer still equals `body`). The screen
  /// calls this from its `onSend` after reading `_composer.text` (the
  /// composer is UI state the controller never touches).
  Future<ChannelSendOutcome> sendBody(String body) async {
    if (body.isEmpty || state.sending) {
      return const ChannelSendOutcome(sent: false, body: '');
    }
    state = state.copyWith(sending: true, chatError: null);
    try {
      await sendChatText(
        gateway: ref.read(gatewayProvider),
        target: _target,
        body: body,
      );
      state = state.copyWith(lastFailedSend: null, chatError: null);
      ref.invalidate(channelSnapshotProvider(name));
      return ChannelSendOutcome(sent: true, body: body);
    } catch (e) {
      state = state.copyWith(
        lastFailedSend: (target: _target, body: body),
        chatError: e.toString(),
      );
      return ChannelSendOutcome(sent: false, body: body);
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Re-sends the last failed body -- 1-1 with React `retryFailedSend`
  /// (use-chat-orchestration.ts L144-149): no-op if there is no recorded
  /// failure for the active target; otherwise re-run [sendBody] with the
  /// stored body. Returns the outcome so the screen clears the composer on
  /// a successful retry (React parity -- the banner's onRetry path).
  Future<ChannelSendOutcome> retryFailedSend() async {
    final failed = state.lastFailedSend;
    if (failed == null || !sameChatTarget(_target, failed.target)) {
      return const ChannelSendOutcome(sent: false, body: '');
    }
    return sendBody(failed.body);
  }

  // Slice-3 attachment SEND -- 1-1 with React's `sendAttachment`
  // (use-chat-orchestration.ts L165): read the picked file's bytes (already
  // base64-encoded by AttachmentPicker), call the Gateway send seam, then
  // invalidate the channel snapshot so the next poll renders the new row.
  // `thumbnailBase64`/`voice` stay null for this atomic. The 50 MB ceiling
  // is enforced in the picker BEFORE bytes are read.
  Future<void> sendAttachment(PickedAttachment attachment) async {
    if (state.sending) return;
    state = state.copyWith(sending: true);
    try {
      await _runTransfer(() => sendChatAttachment(
            gateway: ref.read(gatewayProvider),
            target: _target,
            fileName: attachment.fileName,
            mime: attachment.mime,
            dataBase64: attachment.dataBase64,
            thumbnailBase64: attachment.thumbnailBase64,
          ));
      ref.invalidate(channelSnapshotProvider(name));
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Channel voice SEND -- 1-1 with React `sendVoice` (use-chat-
  /// orchestration.ts L191-210), the channel branch. Reads the recorded
  /// file (path from the VoiceComposer), base64-encodes the bytes, derives
  /// `voice-message.<ext>` from the mime, and calls the Gateway channel
  /// send seam with `voice: VoiceMeta(durationMs, peaksBase64)`.
  Future<void> sendVoice(VoiceSend voice) async {
    if (state.sending) return;
    state = state.copyWith(sending: true);
    try {
      await _runTransfer(() async {
        final file = File(voice.path);
        final bytes = await file.readAsBytes();
        final ext = voice.mime.contains('mp4') ? 'm4a' : 'webm';
        final fileName = 'voice-message.$ext';
        await sendChatAttachment(
          gateway: ref.read(gatewayProvider),
          target: _target,
          fileName: fileName,
          mime: voice.mime,
          dataBase64: base64Encode(bytes),
          voice: VoiceMeta(
            durationMs: voice.durationMs,
            peaksB64: voice.peaksBase64,
          ),
        );
      });
      ref.invalidate(channelSnapshotProvider(name));
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  /// Builds the per-row transfer-action callbacks for the channel message
  /// row's AttachmentCard: download/cancel fire the Gateway seam then
  /// invalidate the channel snapshot (fire-and-forget via `unawaited`).
  /// `onOpen` delegates back to the screen's open handler (passed in) so the
  /// screen wires the viewer + the controller's pending-open arming.
  ChannelAttachmentCallbacks Function(AttachmentView? view) attachmentCallbacks(
    void Function(AttachmentDescriptor descriptor, AttachmentView? view) onOpen,
  ) =>
      (view) => ChannelAttachmentCallbacks(
            busy: state.transferBusy,
            onDownload: (id) => unawaited(_runTransfer(() =>
                downloadChatAttachment(
                  gateway: ref.read(gatewayProvider),
                  target: _target,
                  attachmentId: id,
                ).then((_) => ref.invalidate(channelSnapshotProvider(name))))),
            onCancel: (id) => unawaited(_runTransfer(() => cancelChatAttachment(
                  gateway: ref.read(gatewayProvider),
                  target: _target,
                  attachmentId: id,
                ).then((_) => ref.invalidate(channelSnapshotProvider(name))))),
            onOpen: (descriptor) => onOpen(descriptor, view),
          );

  /// Retry a failed outbound message (React `retryChannelMessage`). Fire-and-
  /// forget via `unawaited`, then invalidate the channel snapshot so the next
  /// poll re-renders the row's delivery status.
  void retryMessage(String messageId) {
    unawaited(retryChatMessage(
      gateway: ref.read(gatewayProvider),
      target: _target,
      messageId: messageId,
    ).then((_) => ref.invalidate(channelSnapshotProvider(name))));
  }

  /// Opens an attachment -- 1-1 with React `openAttachment`
  /// (use-chat-orchestration.ts L243-265). The decision (src / download /
  /// wait) comes from [resolveMediaOpen] (the pure port of the React state
  /// machine). The controller arms `pendingOpen` + kicks the download
  /// (business state + gateway), then returns an immutable intent for the
  /// screen to interpret.
  AttachmentOpenIntent openAttachment(
      AttachmentDescriptor descriptor, AttachmentView? view) {
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
      kind: 'channel',
      host: name,
    );
    if (decision.wait) {
      state = state.copyWith(pendingOpen: descriptor);
    }
    if (decision.download) {
      unawaited(_runTransfer(() => downloadChatAttachment(
            gateway: ref.read(gatewayProvider),
            target: _target,
            attachmentId: descriptor.attachmentId,
          ).then((_) => ref.invalidate(channelSnapshotProvider(name)))));
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
  /// React's `useEffect` (use-chat-orchestration.ts L267-283). Pure with
  /// respect to the snapshot; the side effects are: clear `pendingOpen` in
  /// state (business) + return [ChannelPendingResolution] so the screen
  /// shows the viewer (UI) or drops the pending. Driven by the screen's
  /// `ref.listen` on the channel snapshot.
  ChannelPendingResolution resolvePendingOpen(
      List<AttachmentView> attachments) {
    final pending = state.pendingOpen;
    if (pending == null) return const ChannelPendingResolution.none();
    AttachmentView? view;
    for (final v in attachments) {
      if (v.attachmentId == pending.attachmentId) {
        view = v;
        break;
      }
    }
    if (view == null) return const ChannelPendingResolution.none();
    final localPath = view.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      state = state.copyWith(pendingOpen: null);
      return ChannelPendingResolution.show(pending, localFileSrc(localPath));
    }
    if (view.state == AttachmentState.failed ||
        view.state == AttachmentState.cancelled) {
      state = state.copyWith(pendingOpen: null);
      return const ChannelPendingResolution.drop();
    }
    return const ChannelPendingResolution.none();
  }

  /// Start a 1:1 DM with a channel peer -- 1-1 with React `offerDm`
  /// (use-dm-offers.ts:54): create a private DM invite
  /// (`gateway.createInvite` with the `requestBase` from [inviteFlowProvider]),
  /// send the offer over this channel (`gateway.sendChannelDmOffer`), track
  /// the peer fingerprint as offered, and invalidate `sessionListProvider`.
  /// Returns [ChannelPeerDmResult] carrying the new session id so the screen
  /// navigates to `/dm/<id>` (the controller never navigates). No-op
  /// (returns `noop`) if the peer was already offered.
  Future<ChannelPeerDmResult> onPeerMessage(String peerFingerprint) async {
    if (state.offeredFingerprints.contains(peerFingerprint)) {
      return ChannelPeerDmResult.noop;
    }
    state = state.copyWith(offerBusy: true);
    try {
      final flow = ref.read(inviteFlowProvider);
      final invite = await ref.read(gatewayProvider).createInvite(
            request: StartSessionRequest(
              displayName: flow.displayName,
              listenPort: flow.listenPort,
              staticPeer: flow.staticPeer,
            ),
          );
      await ref.read(gatewayProvider).sendChannelDmOffer(
            channelName: name,
            peerFingerprint: peerFingerprint,
            inviteUri: invite.inviteUri,
          );
      final offered = {...state.offeredFingerprints, peerFingerprint};
      state = state.copyWith(offeredFingerprints: offered);
      ref.invalidate(sessionListProvider);
      return ChannelPeerDmResult(invite.sessionId);
    } finally {
      state = state.copyWith(offerBusy: false);
    }
  }

  /// Leaves the channel -- the gateway close + invalidation + failed-send
  /// clear half of the screen's former `_leave` (React `clearFailedSend` +
  /// `closeChatTarget`). Returns [ChannelLeaveResult] so the screen
  /// navigates to `/sessions` (the controller never navigates).
  ///
  /// The active-conversation-key clear + navigation stay in the screen (the
  /// screen owns the active-conversation lifecycle + navigation); this
  /// method does only the gateway close + invalidation + failed-send clear.
  Future<ChannelLeaveResult> leave() async {
    state = state.copyWith(lastFailedSend: null, chatError: null);
    await closeChatTarget(
      gateway: ref.read(gatewayProvider),
      target: _target,
    );
    ref.invalidate(channelSnapshotProvider(name));
    return const ChannelLeaveResult();
  }
}
