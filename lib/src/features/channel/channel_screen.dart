// S5-1: ChannelScreen route shell -- the minimal, reachable surface for a
// public channel. Mirrors how DmScreen (S4.7) was built surface-by-surface:
// AppBar (channel name + leave IconButton) + a scrolling message list (own
// vs others by FINGERPRINT, not display name -- channels are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// 1-в-1 with the React channel pane (ActiveChatPanes.tsx ActiveChannelChat):
// AppBar (channel name + leave IconButton) + PublicNotice banner +
// ConversationTools (search/filter) + message list (own vs others by
// FINGERPRINT) + composer + peer-status drawer overlay.
//
// Deferred (slice-3): voice sending (VoiceComposer onSendVoice) + drag-drop
// (ChatComposer ChatDropZone). Attachment sending (picker -> sendChannelAttachment)
// + download/cancel transfer seam are ported; AttachmentCard display is ported
// (channel_message_row.dart).
//
// Own-vs-others rule (React MessageLists.tsx ChannelChatList):
// own = message.fromFingerprint == channel.deviceFingerprint. Fingerprint
// comparison (NOT display name) is the key correctness point -- channels
// are multi-party, so two members could share a display name but never a
// device fingerprint. Sender-meta grouping (5-min, same-fingerprint) +
// MultiPartySenderMeta render in channel_message_row.dart.
//
// ConversationTools search/filter is widget-local (`_search` / `_filter`);
// the screen applies `filterChannelMessages` BEFORE `groupChannelMessages`
// (React's filter-then-group order) with the shared `DmSearchEmpty` branch
// when the filter hides every row.
//
// Server state: channelSnapshotProvider (ADR 0010); send calls
// gateway.sendChannel via gatewayProvider (ADR 0013) then invalidates the
// family entry; leave calls gateway.leaveChannel then navigates back to the
// sessions list. The composer is widget-local (ConsumerStatefulWidget).
// Peer-status drawer: mirrors DmScreen wiring. The drawer (PeerStatusDrawer,
// shared with the DM + Group screens) branches internally -- session ->
// channel -> group -> NoActiveSession -- and is rendered here with
// channel: set so it shows ChannelDiagnostics. An AppBar action toggles
// _showPeerStatus; the body is a Stack whose last child is a
// Positioned.fill(PeerStatusDrawer(...)) overlay.
//

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert' show base64Encode;
import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/features/shared/media_viewer.dart'
    show showMediaViewer;
import 'package:mosh/src/features/shared/chat_actions.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor, AttachmentState, StartSessionRequest;
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart'
    show inviteFlowProvider, sessionListProvider;
import 'package:mosh/src/state/active_conversation_key_provider.dart';

import 'package:mosh/src/features/channel/channel_screen_body.dart';
import 'package:mosh/src/features/channel/channel_message_list_view.dart';

/// Channel screen for one public channel. Own vs others is inferred from
/// `ChannelMessage.fromFingerprint` vs the channel's `deviceFingerprint`
/// (React's `from_fingerprint === channel.device_fingerprint` rule -- NOT
/// display name, since channels are multi-party).
class ChannelScreen extends ConsumerStatefulWidget {
  const ChannelScreen({super.key, required this.name});

  final String name;

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _sending = false;
  bool _showPeerStatus = false;
  // Mobile search panel open state -- 1-1 with React `useMobileSearchPanel`
  // (ActiveChatHeader.tsx L103-111): `useState(false)` reset on `resetKey`
  // change. For a channel the reset key is the channel name (`widget.name`),
  // the channel's conversation identity; the AppBar toggle flips it and the
  // body renders `MobileConversationSearch` while true. Gated on the mobile
  // breakpoint (the toggle only renders on mobile).
  bool _mobileSearchOpen = false;
  // The sealed [ChatTarget] for this channel -- routes the screen's
  // send/retry/attachment/leave dispatch through `chat_actions.dart` (the
  // shared DM/channel/group seam, Gap 4) so the gateway method name is
  // decided once here instead of triplicated across the three screens.
  late final ChatTarget _target = ChannelTarget(widget.name);
  // Failed-send retry queue + inline error banner (Gaps 1+3) -- 1-1 with
  // React `use-chat-orchestration.ts` L85-149. `_lastFailedSend` mirrors
  // React's `lastFailedSend: FailedSend | null`; `_chatError` mirrors
  // React's `error` state that drives `<ChatError message={error}>`. On a
  // thrown text send record both + leave the composer untouched (the
  // user's text survives); a successful send clears both. `_leave` clears
  // both on close (React `clearFailedSend`). The success-path
  // composer-clear + ref.invalidate + try-finally + `_sending` flag are
  // unchanged (Gap 5 conditional-clear is a later atom).
  // Ephemeral pending-open descriptor (Gap 2) -- 1-1 with React's
  // `pendingOpen` (use-chat-orchestration.ts L266-283). Set by
  // [_openAttachment] when an image/other attachment is opened before its
  // download finishes; the `ref.listen` in [build] watches the channel
  // snapshot's attachments and resolves it the moment the matching view's
  // `localPath` appears (open the viewer) or its state goes failed/cancelled
  // (drop the pending). Streamable media + already-downloaded opens never
  // set this (they show the viewer immediately).
  AttachmentDescriptor? _pendingOpen;

  ({ChatTarget target, String body})? _lastFailedSend;
  String? _chatError;
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive [filterChannelMessages] before grouping, mirroring
  // DmScreen's `_search` / `_filter` (filter-then-group order).
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;
  // Peer-DM-offer state (React use-dm-offers.ts): the fingerprints the user
  // already messaged this session (disables + relabels the popover button),
  // and a busy flag while a DM-offer send is in flight (disables the
  // button). The set is reset implicitly on screen rebuild for a new
  // channel (the widget is keyed by name in the route), matching React's
  // `prevHostKey` host-change reset.
  final Set<String> _offeredFingerprints = <String>{};
  bool _offerBusy = false;

  @override
  void initState() {
    super.initState();
    // Mark this channel as the active conversation so the unread lifecycle
    // clears its badge on the next focused poll (mirrors React's
    // `activeConversationKey = conversationKey(active)` on screen open).
    // Deferred via a microtask because Riverpod forbids modifying a
    // provider during a widget lifecycle method (initState/build/dispose)
    // -- the set lands after the current build, matching React's effect
    // running after render.
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(activeConversationKeyProvider.notifier)
          .set('channel:${widget.name}');
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  // Reset the mobile search panel when the channel changes -- 1-1 with React's
  // `useMobileSearchPanel` `resetKey` effect (ActiveChatHeader.tsx L107-109:
  // `useEffect(() => { setOpen(false); }, [resetKey])`). The channel name is
  // the reset key; if it changed (the same widget reused for a different
  // channel), the open search panel closes so the new channel does not inherit
  // a stale open mobile search.
  @override
  void didUpdateWidget(covariant ChannelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.name != oldWidget.name) {
      _mobileSearchOpen = false;
    }
  }

  // Resolves [_pendingOpen] against an updated attachments list. Pure with
  // respect to the snapshot; the side effect is showing the viewer + the
  // `setState` that clears the pending. Wired by a `ref.listen` in [build]
  // (Riverpod requires `ref.listen` inside `build`; it dedupes the
  // subscription across rebuilds so it does not re-subscribe each frame).
  void _resolvePendingOpen(List<AttachmentView> attachments) {
    final pending = _pendingOpen;
    if (pending == null) return;
    AttachmentView? view;
    for (final v in attachments) {
      if (v.attachmentId == pending.attachmentId) {
        view = v;
        break;
      }
    }
    if (view == null) return;
    final localPath = view.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      setState(() => _pendingOpen = null);
      showMediaViewer(
        context: context,
        descriptor: pending,
        src: localFileSrc(localPath),
      );
    } else if (view.state == AttachmentState.failed ||
        view.state == AttachmentState.cancelled) {
      setState(() => _pendingOpen = null);
    }
  }

  Future<void> _send() async {
    // Thin wrapper reading the composer; the real send path lives in
    // [_sendBody] so [_retryFailedSend] can re-send the stored failed body
    // without touching the composer first (mirrors React
    // `sendMessageBody(target, body)` taking `body` directly).
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    await _sendBody(body);
  }

  /// Sends a body verbatim -- 1-1 with React `sendMessageBody`. Runs the
  /// full try/catch/finally: on SUCCESS clears `_lastFailedSend` +
  /// `_chatError` (React `setLastFailedSend(null)` + `onError(undefined)`),
  /// clears the composer only if it still equals the sent body (React
  /// parity), and invalidates the channel snapshot; on FAILURE
  /// records `_lastFailedSend = (target, body)` + `_chatError` and leaves
  /// the composer untouched so the user's text survives. The success-path
  /// composer-clear + invalidate + try-finally + `_sending` flag are
  /// unchanged from the pre-Gap-1 `_send`.
  Future<void> _sendBody(String body) async {
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _chatError = null; // React `onError(undefined)` at the top of `run`.
    });
    try {
      await sendChatText(
        gateway: ref.read(gatewayProvider),
        target: _target,
        body: body,
      );
      _lastFailedSend = null;
      _chatError = null;
      // React `setComposer(c => c.trim() === body ? "" : c)` -- only clear the
      // composer if it still holds the sent body, so text the user typed
      // while the send was in flight survives (1-1 with React parity).
      if (_composer.text.trim() == body) {
        _composer.clear();
      }
      ref.invalidate(channelSnapshotProvider(widget.name));
    } catch (e) {
      setState(() {
        _lastFailedSend = (target: _target, body: body);
        _chatError = e.toString();
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Whether the banner's Retry button should be active -- 1-1 with React
  /// `canRetrySend`. `active` is always this screen's `_target`, so it
  /// reduces to a non-null `_lastFailedSend` whose target matches `_target`.
  bool get _canRetrySend =>
      _lastFailedSend != null &&
      sameChatTarget(_target, _lastFailedSend!.target);

  /// Re-sends the last failed body -- 1-1 with React `retryFailedSend`
  /// (use-chat-orchestration.ts L144-149): no-op if there is no recorded
  /// failure for the active target; otherwise re-run [_sendBody] with the
  /// stored body (a successful retry clears both fields, a re-failure
  /// re-records them).
  Future<void> _retryFailedSend() async {
    if (!_canRetrySend) return;
    await _sendBody(_lastFailedSend!.body);
  }

  // Slice-3 attachment SEND -- 1-в-1 with React's `sendAttachment`
  // (use-chat-orchestration.ts L165): read the picked file's bytes (already
  // base64-encoded by AttachmentPicker), call the Gateway send seam, then
  // invalidate the channel snapshot so the next poll renders the new row.
  // `thumbnailBase64`/`voice` stay null for this atomic (thumbnail + voice
  // are later slices). The 50 MB ceiling is enforced in the picker BEFORE
  // bytes are read; an oversized pick routes to `_onAttachmentPickError`.
  Future<void> _sendAttachment(PickedAttachment attachment) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await sendChatAttachment(
        gateway: ref.read(gatewayProvider),
        target: _target,
        fileName: attachment.fileName,
        mime: attachment.mime,
        dataBase64: attachment.dataBase64,
        thumbnailBase64: attachment.thumbnailBase64,
      );
      ref.invalidate(channelSnapshotProvider(widget.name));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Channel voice SEND -- 1-в-1 with React `sendVoice` (use-chat-
  /// orchestration.ts L191-210), the channel branch. Reads the recorded
  /// file (path from the VoiceComposer), base64-encodes the bytes, derives
  /// `voice-message.<ext>` from the mime, and calls the Gateway channel
  /// send seam with `voice: VoiceMeta(durationMs, peaksBase64)`.
  Future<void> _sendVoice(VoiceSend voice) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
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
      ref.invalidate(channelSnapshotProvider(widget.name));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Surfaces mic-permission / start failures from the VoiceComposer
  /// (mirrors React `onVoiceError` -> the screen error SnackBar).
  void _onVoiceError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Surfaces the localized 50 MB limit message when the picker rejects an
  /// oversized file (mirrors React's `onError("Attachment exceeds the 50 MB
  /// limit")`). A SnackBar is the Material idiom for a transient, non-modal
  /// error that does not steal focus from the composer.
  void _onAttachmentPickError(AttachmentPickError error) {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.attachmentTooLargeMessage)),
    );
  }

  Future<void> _leave() async {
    // Clear the failed-send queue + error banner on close -- 1-1 with React
    // `clearFailedSend()` (use-chat-orchestration.ts L94) called in the
    // leave flow. Done before the Gateway close so a slow close does not
    // flash a stale banner.
    setState(() {
      _lastFailedSend = null;
      _chatError = null;
    });
    // Clear the active conversation so the unread lifecycle stops suppressing
    // toasts for this channel (mirrors React's `active` going null on close).
    ref.read(activeConversationKeyProvider.notifier).clear();
    await closeChatTarget(
      gateway: ref.read(gatewayProvider),
      target: _target,
    );
    if (!mounted) return;
    ref.invalidate(channelSnapshotProvider(widget.name));
    context.go(AppRoutes.sessions);
  }

  // Close-flow confirmation -- 1-в-1 with React `useChatCloseFlow` channel
  // branch (use-chat-close-flow.ts L57-65): the leave IconButton opens a
  // ConfirmDialog with `Leave #${label}?` / body / `Leave channel` before
  // the real `_leave` runs. `showConfirmDialog` returns true on confirm,
  // false on cancel/barrier/Esc, so `_leave` only runs on an explicit
  // confirm (mirrors `closeFlow.confirmCloseActive` gating the real close).
  Future<void> _requestLeave() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l.leaveChannelTitle(widget.name),
      body: l.leaveChannelBody,
      confirmLabel: l.leaveChannelConfirm,
      cancelLabel: l.dialogCancel,
    );
    if (confirmed) await _leave();
  }

  /// Builds the per-row transfer-action callbacks for [ChannelMessageRow]'s
  /// AttachmentCard: download/cancel fire the Gateway seam then invalidate
  /// the channel snapshot so the next poll re-renders state + progress
  /// (fire-and-forget via `unawaited`, mirrors DmScreen's
  /// `_attachmentCallbacks`).
  ChannelAttachmentCallbacks _attachmentCallbacks(AttachmentView? view) =>
      ChannelAttachmentCallbacks(
        onDownload: (id) => unawaited(downloadChatAttachment(
          gateway: ref.read(gatewayProvider),
          target: _target,
          attachmentId: id,
        ).then((_) => ref.invalidate(channelSnapshotProvider(widget.name)))),
        onCancel: (id) => unawaited(cancelChatAttachment(
          gateway: ref.read(gatewayProvider),
          target: _target,
          attachmentId: id,
        ).then((_) => ref.invalidate(channelSnapshotProvider(widget.name)))),
        onOpen: (descriptor) => _openAttachment(descriptor, view),
      );

  /// Retry a failed outbound message (React `retryChannelMessage`,
  /// native-messaging-gateway.ts; Rust `channel_retry_message`). Fire-and-
  /// forget via `unawaited`, then invalidate the channel snapshot so the
  /// next poll re-renders the row's delivery status (mirrors the attachment
  /// download/cancel wiring).
 void _retryMessage(String messageId) {
   unawaited(retryChatMessage(
     gateway: ref.read(gatewayProvider),
     target: _target,
     messageId: messageId,
   ).then((_) => ref.invalidate(channelSnapshotProvider(widget.name))));
 }

  /// Start a 1:1 DM with a channel peer -- 1-1 with React `offerDm`
  /// (use-dm-offers.ts:54): create a private DM invite
  /// (`gateway.createInvite` with the `requestBase` from
  /// [inviteFlowProvider], the Flutter name for React's
  /// `createPrivateInvite(requestBase)`), send the offer over this
  /// channel (`gateway.sendChannelDmOffer` -- the seam from c02fac2),
  /// track the peer fingerprint as offered (disables + relabels the
  /// popover button), and navigate to the new DM session
  /// (React `setActive({type: 'dm', id: invite.session_id})` -> the
  /// `/dm/<sessionId>` route). No-op if the peer was already offered.
  Future<void> _onPeerMessage(String peerFingerprint) async {
    if (_offeredFingerprints.contains(peerFingerprint)) return;
    setState(() => _offerBusy = true);
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
            channelName: widget.name,
            peerFingerprint: peerFingerprint,
            inviteUri: invite.inviteUri,
          );
      if (!mounted) return;
      setState(() => _offeredFingerprints.add(peerFingerprint));
      ref.invalidate(sessionListProvider);
      context.go(AppRoutes.dmFor(invite.sessionId));
    } finally {
      if (mounted) setState(() => _offerBusy = false);
    }
  }

  /// Opens the attachment in the in-app [MediaViewer] -- 1-1 with React
  /// `openAttachment` (use-chat-orchestration.ts L243-265). The decision
  /// (src / download / wait) comes from [resolveMediaOpen] (the pure port
  /// of the React state machine) so this stays a thin actor: show the
  /// viewer immediately for already-downloaded + streamable media, or arm
  /// [_pendingOpen] for image/other (the `ref.listen` resolves it once the
  /// download finishes). Reuses [downloadChatAttachment] (Gap 4) for the
  /// download trigger; the host is the channel name (React `active.name`).
  void _openAttachment(AttachmentDescriptor descriptor, AttachmentView? view) {
    final decision = resolveMediaOpen(
      descriptor: descriptor,
      view: view,
      kind: 'channel',
      host: widget.name,
    );
    if (decision.src != null) {
      showMediaViewer(
        context: context,
        descriptor: descriptor,
        src: decision.src!,
      );
    }
    if (decision.wait) {
      setState(() => _pendingOpen = descriptor);
    }
    if (decision.download) {
      unawaited(downloadChatAttachment(
        gateway: ref.read(gatewayProvider),
        target: _target,
        attachmentId: descriptor.attachmentId,
      ).then((_) => ref.invalidate(channelSnapshotProvider(widget.name))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(channelSnapshotProvider(widget.name));
    // Resolve the pending-open descriptor 1-1 with React's `useEffect`
    // (use-chat-orchestration.ts L267-283): when the channel snapshot's
    // attachments update and a pending open is armed, find the matching
    // view; if its `localPath` appeared, show the viewer + clear the
    // pending; if it went failed/cancelled, drop the pending. `ref.listen`
    // is idempotent across rebuilds (Riverpod dedupes the subscription).
    ref.listen<AsyncValue<ChannelSnapshot>>(
      channelSnapshotProvider(widget.name),
      (_, next) {
        final attachments = next.value?.attachments;
        if (attachments == null || attachments.isEmpty) return;
        _resolvePendingOpen(attachments);
      },
    );
    final channelForDrawer = async.value;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          // Mobile search toggle -- 1-1 with React `MobileSearchToggle`
          // (ActiveChatHeader.tsx L113-131), gated on the mobile
          // breakpoint (React `chat-mobile-only` class). Placed first in
          // the actions so it sits left of the peer-status + leave buttons,
          // mirroring React's beforeSearchActions position.
          if (isMobileBreakpoint(context))
            MobileSearchToggle(
              open: _mobileSearchOpen,
              onToggle: () =>
                  setState(() => _mobileSearchOpen = !_mobileSearchOpen),
              l: l,
            ),
          IconButton(
            icon: const Icon(Icons.electrical_services, size: 18),
            tooltip: l.openPeerStatus,
            onPressed: () => setState(() => _showPeerStatus = true),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.channelLeaveLabel,
            onPressed: _requestLeave,
          ),
        ],
      ),
      body: ChannelScreenBody(
        async: async,
        chatError: _chatError,
        canRetrySend: _canRetrySend,
        onRetry: _retryFailedSend,
        search: _search,
        filter: _filter,
        onSearch: (value) => setState(() => _search = value),
        onFilter: (value) => setState(() => _filter = value),
        mobileSearchOpen: _mobileSearchOpen,
        onCloseMobileSearch: () => setState(() => _mobileSearchOpen = false),
        attachmentCallbacks: _attachmentCallbacks,
        onRetryMessage: _retryMessage,
        offeredFingerprints: _offeredFingerprints,
        offerBusy: _offerBusy,
        onPeerMessage: _onPeerMessage,
        composerController: _composer,
        sending: _sending,
        onSend: _send,
        onSendAttachment: _sendAttachment,
        onAttachmentPickError: _onAttachmentPickError,
        onSendVoice: _sendVoice,
        onVoiceError: _onVoiceError,
        showPeerStatus: _showPeerStatus,
        onClosePeerStatus: () => setState(() => _showPeerStatus = false),
        channelForDrawer: channelForDrawer,
        errorForDrawer: errorForDrawer,
        onRefresh: () => ref.invalidate(channelSnapshotProvider(widget.name)),
      ),
    );
  }
}
