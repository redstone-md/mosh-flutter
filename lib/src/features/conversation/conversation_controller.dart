/// The work behind one conversation screen, for any kind.
///
/// It owns what the screen is doing right now -- a send in flight, a failed
/// send waiting to be retried, transfers running, an error to show, a peer
/// already invited, an attachment waiting on its download -- and it talks to
/// the Gateway. It never navigates and never touches the composer (the
/// screen's job), so the methods that could trigger either return a result.
library;

import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart'
    show ConversationAttachmentCallbacks;
import 'package:mosh/src/features/conversation/conversation_state.dart';
import 'package:mosh/src/features/shared/attachment_media_src.dart'
    show
        isViewableMedia,
        localFileSrc,
        resolveLocalAttachmentOpen,
        resolveMediaOpen;
import 'package:mosh/src/features/shared/attachment_open.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show StartSessionRequest;
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor, AttachmentState, AttachmentView;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider, refreshConversation;
import 'package:mosh/src/state/gateway_provider.dart'
    show bridgeFacadeProvider, gatewayProvider;
import 'package:mosh/src/state/org_providers.dart'
    show
        OrgAddPrompt,
        invitingGroupsProvider,
        offeredGroupInvitesProvider,
        orgsProvider;
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;

/// What a recording is called when it is sent. The receiver plays it by its
/// type, so the name only has to end in an extension that matches.
const String _voiceFileBaseName = 'voice-message';
const String _mp4MimeMarker = 'mp4';
const String _mp4VoiceExtension = 'm4a';
const String _webmVoiceExtension = 'webm';

String _voiceFileName(String mime) {
  final extension =
      mime.contains(_mp4MimeMarker) ? _mp4VoiceExtension : _webmVoiceExtension;
  return '$_voiceFileBaseName.$extension';
}

/// One controller per conversation, keyed by its target.
final conversationControllerProvider = NotifierProvider.family<
    ConversationController,
    ConversationControllerState,
    AnyConversationTarget>(ConversationController.new);

class ConversationController extends Notifier<ConversationControllerState> {
  ConversationController(this.target);

  /// The conversation this controller drives. Every Gateway call passes it,
  /// so the kind is named once, here.
  final AnyConversationTarget target;

  @override
  ConversationControllerState build() => const ConversationControllerState();

  /// Re-reads the conversation after a change, and the rail row that shows
  /// it. Which providers those are is the state layer's one kind branch, not
  /// this controller's.
  void refresh() => refreshConversation(ref.invalidate, target.ref);

  /// Runs a transfer while counting it, so the cards know something is busy.
  Future<T> _runTransfer<T>(Future<T> Function() operation) async {
    state = state.copyWith(transferOperations: state.transferOperations + 1);
    try {
      return await operation();
    } finally {
      if (ref.mounted) {
        final running = state.transferOperations;
        state = state.copyWith(
          transferOperations: running > 0 ? running - 1 : 0,
        );
      }
    }
  }

  /// Shows a failed Gateway call in the banner. The bridge's typed error is
  /// kept as its kind, so the screen chooses the wording without reading
  /// the runtime's text.
  void _report(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(chatError: ConversationActionError.of(error));
  }

  /// Sends [body]. On success it clears the failed send and the error and
  /// re-reads the conversation; on failure it keeps the text so Retry can
  /// send it again, and shows the error.
  Future<ConversationSendOutcome> sendBody(String body) async {
    if (body.isEmpty || state.sending) {
      return ConversationSendOutcome.nothingToSend;
    }
    state = state.copyWith(sending: true, chatError: null);
    try {
      await ref.read(gatewayProvider).send(target, body: body);
      state = state.copyWith(lastFailedBody: null, chatError: null);
      refresh();
      return ConversationSendOutcome(sent: true, body: body);
    } catch (error) {
      state = state.copyWith(lastFailedBody: body);
      _report(error);
      return ConversationSendOutcome(sent: false, body: body);
    } finally {
      if (ref.mounted) state = state.copyWith(sending: false);
    }
  }

  /// Sends the last failed text again.
  Future<ConversationSendOutcome> retryFailedSend() async {
    final body = state.lastFailedBody;
    if (body == null) return ConversationSendOutcome.nothingToSend;
    return sendBody(body);
  }

  /// The [[Typing indicator]] emit-on-input hook: hands the runtime the
  /// keystroke, which throttles its wire frame on its own ~3 s cadence
  /// and does nothing for kinds that never carry typing (channels).
  void signalTyping() {
    unawaited(
        ref.read(gatewayProvider).typingSignal(target).catchError((_) {}));
  }

  /// The conversation is on screen: hands the runtime the view mark, which
  /// auto-triggers the DM read receipts for every not-yet-read counterpart
  /// message when the toggle is on. The runtime owns the toggle check, the
  /// per-message frames and the idempotence; a failure is silent — the next
  /// poll retries, and a banner over a receipt is noise.
  ///
  /// The sync guard matters: flutter_rust_bridge throws synchronously
  /// (before any Future) when the library was never initialized — which is
  /// every widget test. `catchError` never sees that throw, so the call is
  /// wrapped, not just the future.
  void markViewed() {
    try {
      final future = ref.read(gatewayProvider).markViewed(target);
      unawaited(future.catchError((_) {}));
    } catch (_) {
      // No Rust behind the gateway (test runtime): the receipts are
      // runtime-side state anyway, and the next poll retries.
    }
  }

  /// Sends a picked file. The picker has already read the bytes and enforced
  /// the size limit.
  Future<void> sendAttachment(PickedAttachment attachment) async {
    await _send(() => ref.read(gatewayProvider).sendAttachment(
          target,
          fileName: attachment.fileName,
          mime: attachment.mime,
          dataBase64: attachment.dataBase64,
          thumbnailBase64: attachment.thumbnailBase64,
        ));
  }

  /// Sends a recording as a voice message. The duration and the waveform
  /// travel with it so the row can render the player.
  Future<void> sendVoice(VoiceSend voice) async {
    await _send(() async {
      final bytes = await File(voice.path).readAsBytes();
      await ref.read(gatewayProvider).sendAttachment(
            target,
            fileName: _voiceFileName(voice.mime),
            mime: voice.mime,
            dataBase64: base64Encode(bytes),
            voice: VoiceMeta(
              durationMs: voice.durationMs,
              peaksB64: voice.peaksBase64,
            ),
          );
    });
  }

  /// The shared body of the two file sends: block a second send, run the
  /// upload as a counted transfer, then re-read the conversation. A failure
  /// goes to the banner without a Retry: the file is not kept.
  Future<void> _send(Future<void> Function() upload) async {
    if (state.sending) return;
    state = state.copyWith(sending: true, chatError: null);
    try {
      await _runTransfer(upload);
      refresh();
    } catch (error) {
      _report(error);
    } finally {
      if (ref.mounted) state = state.copyWith(sending: false);
    }
  }

  /// The gateway calls behind the card's download / cancel affordances,
  /// deduped so each site names the attachment id once.
  Future<void> _downloadAttachment(Gateway g, String id) =>
      g.downloadAttachment(target, attachmentId: id);

  Future<void> _cancelAttachment(Gateway g, String id) =>
      g.cancelAttachment(target, attachmentId: id);

  /// Builds the attachment card's actions for one row. [onOpen] goes back to
  /// the screen, which owns the viewer.
  ConversationAttachmentCallbacks Function(AttachmentView? view)
      attachmentCallbacks(
    void Function(AttachmentDescriptor descriptor, AttachmentView? view) onOpen,
  ) =>
          (view) => ConversationAttachmentCallbacks(
                busy: state.transferBusy,
                onDownload: (id) =>
                    _transferAttachment((g) => _downloadAttachment(g, id)),
                onCancel: (id) =>
                    _transferAttachment((g) => _cancelAttachment(g, id)),
                onOpen: (descriptor) => onOpen(descriptor, view),
              );

  /// Starts a transfer and re-reads the conversation when it settles. The
  /// progress shows up in the next poll, so nothing waits on the future; a
  /// failure lands in the banner.
  void _transferAttachment(Future<void> Function(Gateway gateway) call) {
    unawaited(_runTransfer(
            () => call(ref.read(gatewayProvider)).then((_) => refresh()))
        .catchError(_report));
  }

  /// Sends a failed message again. The new delivery state shows up in the
  /// next poll; a failure lands in the banner.
  void retryMessage(String messageId) {
    unawaited(ref
        .read(gatewayProvider)
        .retry(target, messageId: messageId)
        .then((_) => refresh())
        .catchError(_report));
  }

  /// Opens an attachment. A downloaded file opens straight away, streamable
  /// media plays while it downloads, and anything else starts the download
  /// and waits: the screen shows it once [resolvePendingOpen] says so.
  AttachmentOpenIntent openAttachment(
    AttachmentDescriptor descriptor,
    AttachmentView? view,
  ) {
    final local =
        resolveLocalAttachmentOpen(descriptor: descriptor, view: view);
    if (local is! AttachmentNoopOpenIntent) return local;
    if (!isViewableMedia(descriptor.mime)) {
      return const AttachmentNoopOpenIntent();
    }
    final decision = resolveMediaOpen(
      descriptor: descriptor,
      view: view,
      kind: target.kind.name,
      host: target.id,
    );
    if (decision.wait) state = state.copyWith(pendingOpen: descriptor);
    if (decision.download) {
      _transferAttachment(
          (g) => _downloadAttachment(g, descriptor.attachmentId));
    }
    return switch (decision.src) {
      null => const AttachmentNoopOpenIntent(),
      final src => AttachmentMediaOpenIntent(descriptor: descriptor, src: src),
    };
  }

  /// Checks a waiting attachment against a fresh transfer list. Called by the
  /// screen every time the conversation is re-read.
  ConversationPendingOpen resolvePendingOpen(List<AttachmentView> views) {
    final pending = state.pendingOpen;
    if (pending == null) return const ConversationPendingNone();
    AttachmentView? view;
    for (final candidate in views) {
      if (candidate.attachmentId == pending.attachmentId) {
        view = candidate;
        break;
      }
    }
    if (view == null) return const ConversationPendingNone();
    final localPath = view.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      state = state.copyWith(pendingOpen: null);
      return ConversationPendingShow(pending, localFileSrc(localPath));
    }
    // A failed/cancelled transfer clears the wait: nothing will arrive.
    if (view.state == AttachmentState.failed ||
        view.state == AttachmentState.cancelled) {
      state = state.copyWith(pendingOpen: null);
      return const ConversationPendingDropped();
    }
    return const ConversationPendingNone();
  }

  /// Invites a peer of this channel or group to a private DM: mint an
  /// invite, send it over the conversation, and remember the peer. Returns
  /// the new DM so the screen can open it. The invite mint and the offer
  /// send are 1:1 bridge mirrors, so they go through the facade (ADR 0025).
  Future<ConversationPeerDmResult> onPeerMessage(String peerFingerprint) async {
    final host = target;
    if (host is! DmOfferHost) return ConversationPeerDmResult.none;
    if (state.offeredFingerprints.contains(peerFingerprint)) {
      return ConversationPeerDmResult.none;
    }
    state = state.copyWith(offerBusy: true);
    try {
      final flow = ref.read(inviteFlowProvider);
      final invite = await ref.read(bridgeFacadeProvider).createInvite(
            request: StartSessionRequest(
              displayName: flow.displayName,
              listenPort: flow.listenPort,
              staticPeer: flow.staticPeer,
            ),
          );
      // The channel and group offers are distinct bridge calls: the one
      // kind branch, exhaustive over the sealed DmOfferHost kinds.
      await switch (host) {
        ChannelTarget() => ref.read(bridgeFacadeProvider).sendChannelDmOffer(
              channelName: host.id,
              peerFingerprint: peerFingerprint,
              inviteUri: invite.inviteUri,
            ),
        GroupTarget() => ref.read(bridgeFacadeProvider).sendGroupDmOffer(
              groupId: host.id,
              peerFingerprint: peerFingerprint,
              inviteUri: invite.inviteUri,
            ),
      };
      state = state.copyWith(
        offeredFingerprints: {...state.offeredFingerprints, peerFingerprint},
      );
      ref.invalidate(conversationListProvider(ConversationKind.dm));
      return ConversationPeerDmResult(invite.sessionId);
    } finally {
      state = state.copyWith(offerBusy: false);
    }
  }

  /// Adds the org members missing from this group. Org admins only, and only
  /// on a group.
  void inviteMembers(OrgAddPrompt prompt) {
    final group = target;
    if (group is! GroupTarget) return;
    final peerIds = prompt.missingPeerIds;
    if (peerIds.isEmpty) return;
    ref.read(invitingGroupsProvider.notifier).start(group.id);
    unawaited(ref
        .read(bridgeFacadeProvider)
        .orgGroupInviteMembers(
          orgPubkey: prompt.orgPubkey,
          groupId: group.id,
          memberPeerIds: peerIds,
        )
        .then((_) => ref
            .read(offeredGroupInvitesProvider.notifier)
            .markInvited(group.id, peerIds))
        .catchError((_) {})
        .whenComplete(() {
      ref.read(invitingGroupsProvider.notifier).finish(group.id);
      ref.invalidate(orgsProvider);
      refresh();
    }));
  }

  /// Shows a ready-made sentence in the error banner without touching the
  /// failed-send state, so an error from elsewhere never offers to re-send
  /// a message.
  void showError(String? message) {
    state = state.copyWith(
      chatError: message == null ? null : ConversationActionError.text(message),
    );
  }

  /// Closes the DM, leaves the channel, or closes the group. Returns whether
  /// it happened: the screen navigates away only then, and a failure stays
  /// in the banner.
  Future<bool> leave() async {
    state = state.copyWith(lastFailedBody: null, chatError: null);
    try {
      await ref.read(gatewayProvider).leave(target);
    } catch (error) {
      _report(error);
      return false;
    }
    refresh();
    return true;
  }
}
