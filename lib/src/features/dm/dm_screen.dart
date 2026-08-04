// S4.7: DM screen for slice-one. App bar (peer display name) + scrolling
// message list (own vs peer by alignment/color; own = `fromDevice ==
// snapshot.displayName`, the React `from_device === ownDeviceName` rule) +
// composer + crypto footer. Mirrors the React ActiveDmChat
// (ActiveChatPanes.tsx + MessageLists.tsx + ChatComposer.tsx).
//
// Grouping: React `DmMessageRow` rule -- a 5-min window groups consecutive
// same-`fromDevice` rows (only the first renders an avatar + sender-meta;
// grouped rows render a spacer). Chronological, then reversed (newest at
// bottom). MLS badge in the sender meta ([SenderMeta]).
//
// Search + filter: React `filterMessages` BEFORE grouping, then reverses
// (matching `DmChatList`/`MessageLists`). ConversationTools sits above the
// list; `DmSearchEmpty` renders when the filter hid every row.
//
// Attachments (Gap 2): each row wires an `AttachmentCard` via
// `_attachmentCallbacks` -- download/cancel hit the Gateway seam (Gap 4),
// open routes through the in-app `MediaViewer` (1-1 with React
// `openAttachment`): already-downloaded opens show the local file,
// streamable media streams `moshmedia.localhost` while downloading, and
// image/other arms a pending-open resolved by the `ref.listen` once the
// download finishes. Deferred: call events, the full poll loop.
//
// Server state: activeSessionProvider (ADR 0010); send calls
// gateway.sendMessage via gatewayProvider (ADR 0013) and invalidates the
// family entry. Composer + search/filter + peer-status drawer are widget-
// local (ConsumerStatefulWidget). Slice-one: refresh on init + after send.
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert' show base64Encode;

import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/features/shared/chat_drop_zone.dart' show ChatDropZone;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/attachment_card.dart';
import 'package:mosh/src/features/dm/dm_message_list.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/dm/conversation_composer.dart';
import 'package:mosh/src/features/dm/voice_call_layer.dart' show VoiceCallLayer, startVoiceCall;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/features/shared/media_viewer.dart'
    show showMediaViewer;
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/features/shared/chat_actions.dart';
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/fingerprint_badge.dart';
import 'package:mosh/src/features/dm/chat_header_menu.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor, AttachmentState, SessionSnapshot;
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';

/// Direct-message screen for one session. Own vs peer is inferred from
/// `ChatMessage.fromDevice` vs the session's `displayName` (React's
/// `from_device === ownDeviceName` rule).
class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _sending = false;
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive `filterDmMessages` before grouping.
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;
  bool _showPeerStatus = false;
  // Mobile search panel open state -- 1-1 with React `useMobileSearchPanel`
  // (ActiveChatHeader.tsx L103-111): a `useState(false)` reset to false on
  // `resetKey` (sessionId) change. The AppBar `MobileSearchToggle` flips it;
  // the body renders `MobileConversationSearch` while true. Gated on the
  // mobile breakpoint (the toggle only renders on mobile), so on desktop this
  // stays false and the desktop `ConversationTools` row renders instead.
  bool _mobileSearchOpen = false;

  // Ephemeral confirmed-fingerprint set (React `confirmedFingerprints`
  // useState, use-chat-close-flow.ts). Widget-local per ADR 0010; purely
  // client-side, NOT a Gateway call. `_leave` removes the sessionId from
  // this set on close (mirrors React `confirmCloseActive`'s
  // `confirmedFingerprints.delete(target.id)` cleanup).
  Set<String> _confirmedFingerprints = {};

  // The sealed [ChatTarget] for this DM session -- routes the screen's
  // send/retry/attachment/leave dispatch through `chat_actions.dart` (the
  // shared DM/channel/group seam, Gap 4) so the gateway method name is
  // decided once here instead of triplicated across the three screens.
  late final ChatTarget _target = DmTarget(widget.sessionId);

  // Failed-send retry queue + inline error banner (Gaps 1+3) -- 1-1 with
  // React `use-chat-orchestration.ts` L85-149. `_lastFailedSend` mirrors
  // React's `lastFailedSend: FailedSend | null` (the target + body of the
  // most recent failed text send); `_chatError` mirrors React's `error`
  // state that drives `<ChatError message={error} onRetry={...}>`. On a
  // thrown text send we record both (so the Retry button re-sends the body
  // and the banner shows the error) and LEAVE the composer untouched (the
  // user's text is preserved, matching React). A successful send clears
  // both. `_leave` clears both on navigation away (React `clearFailedSend`
  // in the close flow). The success-path composer-clear + ref.invalidate +
  // try-finally + `_sending` flag are unchanged (Gap 5 conditional-clear is
  // a later atom; this port keeps the existing unconditional clear).
  // Ephemeral pending-open descriptor (Gap 2) -- 1-1 with React's
  // `pendingOpen` (use-chat-orchestration.ts L266-283). Set by
  // [_openAttachment] when an image/other attachment is opened before its
  // download finishes; the `ref.listen` in [build] watches the session
  // snapshot's attachments and resolves it the moment the matching view's
  // `localPath` appears (open the viewer) or its state goes failed/cancelled
  // (drop the pending). Streamable media + already-downloaded opens never
  // set this (they show the viewer immediately).
  AttachmentDescriptor? _pendingOpen;

  ({ChatTarget target, String body})? _lastFailedSend;
  String? _chatError;

  @override
  void initState() {
    super.initState();
    // Mark this DM as the active conversation so the unread lifecycle clears
    // its badge on the next focused poll (mirrors React's
    // `activeConversationKey = conversationKey(active)` on screen open).
    // Deferred via a microtask because Riverpod forbids modifying a
    // provider during a widget lifecycle method (initState/build/dispose)
    // -- the set lands after the current build, matching React's effect
    // running after render.
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(activeConversationKeyProvider.notifier)
          .set('dm:${widget.sessionId}');
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  // Reset the mobile search panel when the session changes -- 1-1 with React's
  // `useMobileSearchPanel` `resetKey` effect (ActiveChatHeader.tsx L107-109:
  // `useEffect(() => { setOpen(false); }, [resetKey])`). The session id is
  // the reset key; if it changed (the same widget is reused for a different
  // DM), the open search panel closes so the new conversation does not inherit
  // a stale open mobile search.
  @override
  void didUpdateWidget(covariant DmScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId) {
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
    // Thin wrapper 1-1 with React's `_send` reading the composer -- the
    // real send path lives in [_sendBody] so [_retryFailedSend] can re-send
    // the stored failed body without touching the composer first (mirrors
    // React `sendMessageBody(target, body)` taking `body` directly).
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    await _sendBody(body);
  }

  /// Sends a body verbatim -- 1-1 with React `sendMessageBody`. Runs the
  /// full try/catch/finally: on SUCCESS clears `_lastFailedSend` +
  /// `_chatError` (React `setLastFailedSend(null)` + `onError(undefined)`),
  /// clears the composer only if it still equals the sent body (React
  /// parity), and invalidates the providers; on FAILURE records
  /// `_lastFailedSend = (target, body)` + `_chatError` (React
  /// `setLastFailedSend({target, body})`) and leaves the composer untouched
  /// so the user's text survives. The `finally` clears `_sending` exactly as
  /// before; the success-path composer-clear + invalidate + try-finally +
  /// `_sending` flag are unchanged from the pre-Gap-1 `_send`.
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
      ref.invalidate(activeSessionProvider(widget.sessionId));
      ref.invalidate(sessionListProvider);
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
  /// `canRetrySend = Boolean(active && lastFailedSend && sameChatTarget(active,
  /// lastFailedSend.target))`. `active` is always this screen's `_target`
  /// (the DM screen only ever renders one session), so it reduces to a
  /// non-null `_lastFailedSend` whose target matches `_target`.
  bool get _canRetrySend =>
      _lastFailedSend != null &&
      sameChatTarget(_target, _lastFailedSend!.target);

  /// Re-sends the last failed body -- 1-1 with React `retryFailedSend`
  /// (use-chat-orchestration.ts L144-149): if there is no recorded failure
  /// for the active target, no-op; otherwise re-run the full send path with
  /// the stored body (which re-enters [_sendBody]'s try/catch, so a
  /// successful retry clears both fields and a re-failure re-records them).
  Future<void> _retryFailedSend() async {
    if (!_canRetrySend) return;
    await _sendBody(_lastFailedSend!.body);
  }

  /// DM attachment SEND -- 1-в-1 with React's `sendAttachment`
  /// (use-chat-orchestration.ts L165), the dm branch. Reads the picked
  /// file's bytes (already base64-encoded by AttachmentPicker), calls the
  /// Gateway DM send seam, then invalidates the session provider so the
  /// next poll renders the new row. `thumbnailBase64`/`voice` come from the
  /// picker (thumbnail is the 320px JPEG for image picks; voice stays null
  /// for this atomic -- the voice composer is a later slice). The 50 MB
  /// ceiling is enforced in the picker BEFORE bytes are read; an oversized
  /// pick routes to `_onAttachmentPickError`.
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
      ref.invalidate(activeSessionProvider(widget.sessionId));
      ref.invalidate(sessionListProvider);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// DM voice SEND -- 1-в-1 with React `sendVoice` (use-chat-orchestration
  /// L191-210), the dm branch. Reads the recorded file (path from the
  /// VoiceComposer), base64-encodes the bytes, derives a deterministic
  /// `voice-message.<ext>` file name from the mime, and calls the Gateway
  /// DM send seam with `voice: VoiceMeta(durationMs, peaksBase64)` so the
  /// row renders as a voice message. Mirrors React `sendVoice` which builds
  /// `new File([voice.blob], fileName, {type: voice.mime})` + the VoiceMeta.
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
      ref.invalidate(activeSessionProvider(widget.sessionId));
      ref.invalidate(sessionListProvider);
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

  /// Builds the per-row transfer-action callbacks for [AttachmentCard]:
  /// download/cancel fire the Gateway seam (99bc9d9) then invalidate the
  /// session provider so the next poll re-renders state + progress
  /// (fire-and-forget via `unawaited`).
  DmAttachmentCallbacks _attachmentCallbacks(AttachmentView? view) =>
      DmAttachmentCallbacks(
        onDownload: (id) => unawaited(downloadChatAttachment(
          gateway: _gateway,
          target: _target,
          attachmentId: id,
        ).then((_) => ref.invalidate(activeSessionProvider(_sessionId)))),
        onCancel: (id) => unawaited(cancelChatAttachment(
          gateway: _gateway,
          target: _target,
          attachmentId: id,
        ).then((_) => ref.invalidate(activeSessionProvider(_sessionId)))),
        onOpen: (descriptor) => _openAttachment(descriptor, view),
      );

  /// Retry a failed outbound DM message (React `retryDmMessage`,
  /// native-messaging-gateway.ts; Rust `private_dm_retry_message`).
  /// Fire-and-forget via `unawaited`, then invalidate the session snapshot
  /// so the next poll re-renders the row's delivery status (mirrors the
  /// attachment download/cancel wiring + the channel/group retry seam).
  void _retryMessage(String messageId) {
    unawaited(retryChatMessage(
      gateway: _gateway,
      target: _target,
      messageId: messageId,
    ).then((_) => ref.invalidate(activeSessionProvider(_sessionId))));
  }

  /// Opens the attachment in the in-app [MediaViewer] -- 1-1 with React
  /// `openAttachment` (use-chat-orchestration.ts L243-265). The decision
  /// (src / download / wait) comes from [resolveMediaOpen] (the pure port
  /// of the React state machine) so this stays a thin actor: show the
  /// viewer immediately for already-downloaded + streamable media, or arm
  /// [_pendingOpen] for image/other (the `ref.listen` resolves it once the
  /// download finishes). Reuses [downloadChatAttachment] (Gap 4) for the
  /// download trigger; the host is the DM session id (React `active.id`).
  void _openAttachment(AttachmentDescriptor descriptor, AttachmentView? view) {
    final decision = resolveMediaOpen(
      descriptor: descriptor,
      view: view,
      kind: 'dm',
      host: widget.sessionId,
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
        gateway: _gateway,
        target: _target,
        attachmentId: descriptor.attachmentId,
      ).then((_) => ref.invalidate(activeSessionProvider(_sessionId))));
    }
  }

  String get _sessionId => widget.sessionId;
  Gateway get _gateway => ref.read(gatewayProvider);

  void _confirmFingerprint() => setState(() =>
      _confirmedFingerprints = {..._confirmedFingerprints, widget.sessionId});

  /// Closes the active DM session -- the real half of the close-flow
  /// (React `confirmCloseActive` for the `dm` branch, use-chat-close-flow.ts
  /// L113-119). Calls `gateway.closeSession`, then mirrors React's
  /// `confirmedFingerprints.delete(target.id)` cleanup (the confirmed
  /// fingerprint for this session is no longer relevant once the session
  /// is gone), invalidates the session family entry so the sessions list
  /// refreshes, and navigates back to the sessions list. Matches the
  /// channel/group `_leave` invalidation + `context.go(AppRoutes.sessions)`
  /// pattern.
  Future<void> _leave() async {
    // Clear the failed-send queue + error banner on close -- 1-1 with React
    // `clearFailedSend()` (use-chat-orchestration.ts L94) called in the
    // onClose/leave flow (private-dm-screen.tsx L137). Done before the
    // Gateway close so a slow close does not flash a stale banner.
    setState(() {
      _lastFailedSend = null;
      _chatError = null;
    });
    // Clear the active conversation so the unread lifecycle stops suppressing
    // toasts for this DM (mirrors React's `active` going null on close).
    ref.read(activeConversationKeyProvider.notifier).clear();
    await closeChatTarget(
      gateway: ref.read(gatewayProvider),
      target: _target,
    );
    if (!mounted) return;
    setState(() => _confirmedFingerprints = _confirmedFingerprints
      ..remove(widget.sessionId));
    ref.invalidate(activeSessionProvider(widget.sessionId));
    ref.invalidate(sessionListProvider);
    // Desktop routes to /chat (branch B initialLocation) so the inline
    // NewSessionPanel reappears; mobile keeps the rail (current behavior).
    final target =
        isMobileBreakpoint(context) ? AppRoutes.sessions : AppRoutes.chat;
    context.go(target);
  }

  /// Close-flow confirmation -- 1-в-1 with React `useChatCloseFlow` dm branch
  /// (use-chat-close-flow.ts L46-56): the leave IconButton opens a
  /// ConfirmDialog with `Delete chat with {label}?` / body / `Delete chat`
  /// before the real `_leave` runs. The `label` is the peer display name,
  /// falling back to the sessionId when `peerDisplayName` is empty (the
  /// existing `title` rule; React's `session ? sessionLabel(session) :
  /// "this private chat"` fallback is unreachable here -- the DM screen
  /// always has a session -- but the sessionId fallback mirrors its shape
  /// defensively). `showConfirmDialog` returns true on confirm, false on
  /// cancel/barrier/Esc, so `_leave` only runs on an explicit confirm
  /// (mirrors `closeFlow.confirmCloseActive` gating the real close).
  Future<void> _requestLeave() async {
    final l = AppLocalizations.of(context)!;
    final async = ref.read(activeSessionProvider(widget.sessionId));
    final label = async.maybeWhen(
      data: (s) => s.peerDisplayName.isEmpty ? s.sessionId : s.peerDisplayName,
      orElse: () => widget.sessionId,
    );
    final confirmed = await showConfirmDialog(
      context: context,
      title: l.deleteChatTitle(label),
      body: l.deleteChatBody,
      confirmLabel: l.deleteChatConfirm,
      cancelLabel: l.dialogCancel,
    );
    if (confirmed) await _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    // Resolve the pending-open descriptor 1-1 with React's `useEffect`
    // (use-chat-orchestration.ts L267-283): when the session snapshot's
    // attachments update and a pending open is armed, find the matching
    // view; if its `localPath` appeared, show the viewer + clear the
    // pending; if it went failed/cancelled, drop the pending. `ref.listen`
    // is idempotent across rebuilds (Riverpod dedupes the subscription).
    ref.listen<AsyncValue<SessionSnapshot>>(
      activeSessionProvider(widget.sessionId),
      (_, next) {
        final attachments = next.value?.attachments;
        if (attachments == null || attachments.isEmpty) return;
        _resolvePendingOpen(attachments);
      },
    );
    final s = async.value;
    final mlsState = s?.state ?? '';
    final fingerprint = s?.fingerprint ?? '';
    final confirmed = fingerprint.isNotEmpty &&
        _confirmedFingerprints.contains(widget.sessionId);
    final sessionForDrawer = s;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s == null || s.peerDisplayName.isEmpty
                  ? widget.sessionId
                  : s.peerDisplayName),
              Text(
                  confirmed
                      ? l.dmSubtitleConfirmed(mlsState)
                      : l.dmSubtitleUnverified(mlsState),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
       actions: [
          FingerprintBadge(
              fingerprint: fingerprint,
              confirmed: confirmed,
              onConfirm: _confirmFingerprint),
          // Mobile search toggle -- 1-1 with React `MobileSearchToggle`
          // (ActiveChatHeader.tsx L113-131): a ghost icon button in the
          // header `actions:` that opens/closes the mobile search panel.
          // Gated on the mobile breakpoint (the CSS `chat-mobile-only`
          // class hides it on desktop); on desktop the toggle is absent and
          // the desktop `ConversationTools` row renders in the body. Placed
          // after the FingerprintBadge (React `beforeSearchActions`) and
          // before the phone/peer-status/close buttons (React
          // `afterSearchActions`), mirroring the React header order.
          if (isMobileBreakpoint(context))
            MobileSearchToggle(
              open: _mobileSearchOpen,
              onToggle: () =>
                  setState(() => _mobileSearchOpen = !_mobileSearchOpen),
              l: l,
            ),
          // Mobile kebab menu -- 1-1 with React `ChatHeaderMenu`
          // (ChatHeaderMenu.tsx) prepended with the filter toggle via
          // `conversationMenuActions` (ActiveChatHeader.tsx ~L155-170).
          // Self-gates to mobile (the widget returns SizedBox.shrink() on
          // desktop); React places it last in `chat-header-actions`, so it
          // sits rightmost on mobile. The DM `menuActions` (ActiveChatPanes
          // ActiveDmChat ~L38-49): confirm/confirmed fingerprint (disabled
          // when confirmed; onSelect -> onConfirm -> _confirmFingerprint)
          // + Delete chat (danger tone; onSelect -> onClose ->
          // _requestLeave). The filter toggle is FIRST: if the current
          // filter is "attachments" the item is "All" (IconMessageCircle ->
          // Icons.chat_bubble_outline) -> onFilter(all); otherwise "Files"
          // (IconPaperclip -> Icons.attach_file) -> onFilter(attachments).
          ChatHeaderMenu(
            l: l,
            actions: [
              if (_filter == ConversationFilter.attachments)
                ChatHeaderMenuAction(
                  label: l.chatFilterAll,
                  icon: Icons.chat_bubble_outline,
                  onSelect: () =>
                      setState(() => _filter = ConversationFilter.all),
                )
              else
                ChatHeaderMenuAction(
                  label: l.chatFilterAttachments,
                  icon: Icons.attach_file,
                  onSelect: () => setState(
                      () => _filter = ConversationFilter.attachments),
                ),
              ChatHeaderMenuAction(
                label: confirmed
                    ? l.inviteConfirmedButton
                    : l.inviteConfirmButton,
                icon: Icons.verified_user,
                disabled: confirmed,
                onSelect: _confirmFingerprint,
              ),
              ChatHeaderMenuAction(
                label: l.deleteChatConfirm,
                icon: Icons.delete_outline,
                danger: true,
                onSelect: _requestLeave,
              ),
            ],
          ),
          // Start-call button -- 1-в-1 with React's `onStartCall` header
          // action (private-dm-screen.tsx L382 -> useVoiceCallOrchestration
          // startCall). Icons.phone mirrors tabler's IconPhone; the
          // outgoing-call modal opens once the snapshot reflects the
          // `outgoing_call` field (the VoiceCallLayer watches it).
          IconButton(
            icon: const Icon(Icons.phone, size: 18),
            tooltip: l.callStart,
            onPressed: () async {
              final err = await startVoiceCall(ref, widget.sessionId);
              if (!context.mounted) return;
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err.toString())),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.electrical_services, size: 18),
            tooltip: l.openPeerStatus,
            onPressed: () => setState(() => _showPeerStatus = true),
          ),
          // Leave/close-session button -- 1-в-1 with React's DM leave button
          // in ActiveChatHeader `afterSearchActions` (ActiveChatPanes.tsx
          // L122-130: IconX, aria-label/title = `shellText.closeSession`,
          // onClick = closeFlow.closeActive -> _requestLeave). Placed LAST in
          // AppBar `actions` so it sits rightmost (React's
          // afterSearchActions is right-of-search, so the leave button is
          // the rightmost header button). Icons.close mirrors React's IconX;
          // size 18 matches the peer-status IconButton for header
          // consistency (React uses 16, but the sibling button is 18 here).
          // React marks this `chat-desktop-only`; on mobile the kebab's
          // "Delete chat" item (above) is the close entry point instead.
          if (!isMobileBreakpoint(context))
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: l.shellCloseSession,
              onPressed: _requestLeave,
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Inline error banner (Gap 3) -- 1-1 with React
                // private-dm-screen.tsx L337-341
                // `{!showWelcome && error ? <ChatError message={error}
                // onRetry={canRetrySend ? retryFailedSend : undefined} /> :
                // null}`. The DM screen is never on the welcome state (it
                // always has a session), so the gate is just `_chatError !=
                // null`. The Retry button is active iff [_canRetrySend].
                if (_chatError != null)
                  ChatErrorBanner(
                    message: _chatError!,
                    onRetry: _canRetrySend ? _retryFailedSend : null,
                  ),
                // Desktop search/filter row -- gated on the desktop
                // breakpoint (React hides `.conversation-tools-desktop` at
                // `max-width: 580px`). On desktop the row renders exactly as
                // before (byte-identical); on mobile the compact trio below
                // replaces it.
                if (!isMobileBreakpoint(context))
                  ConversationTools(
                    search: _search,
                    filter: _filter,
                    onSearch: (value) => setState(() => _search = value),
                    onFilter: (value) => setState(() => _filter = value),
                    l: l,
                  ),
                // Mobile search/filter trio -- 1-1 with React
                // ActiveChatHeader `mobileSearchOpen ? <MobileConversation
                // Search/> : null` + the always-rendered
                // `MobileConversationFilterNotice` (null-collapses when
                // filter == all). Only on mobile (the toggle is gated in
                // the AppBar on the same breakpoint).
                if (isMobileBreakpoint(context)) ...[
                  if (_mobileSearchOpen)
                    MobileConversationSearch(
                      search: _search,
                      onSearch: (value) => setState(() => _search = value),
                      onClose: () =>
                          setState(() => _mobileSearchOpen = false),
                      l: l,
                    ),
                  MobileConversationFilterNotice(
                    filter: _filter,
                    onFilter: (value) => setState(() => _filter = value),
                    l: l,
                  ),
                ],
                // ChatDropZone wraps the message list so a desktop file drop
                // reuses the SAME onAttach/onError pair the paperclip uses
                // (ChatComposer.tsx:8-43 React parity). DM has no separate
                // ready flag -- async.when's data branch gates the list render.
                // Expanded stays the Column's direct child (Flex parent data);
                // ChatDropZone sits inside it wrapping the list content.
                Expanded(
                  child: ChatDropZone(
                    disabled: _sending,
                    onAttach: _sendAttachment,
                    onError: _onAttachmentPickError,
                    child: async.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text(e.toString())),
                      data: (s) {
                        if (s.messages.isEmpty) return _Empty(l: l);
                        final filtered =
                            filterDmMessages(s.messages, _search, _filter);
                        if (filtered.isEmpty) {
                          return DmSearchEmpty(filter: _filter, l: l);
                        }
                        return DmMessageListView(
                          ownDeviceName: s.displayName,
                          grouped: groupDmMessages(filtered).reversed.toList(),
                          attachments: s.attachments,
                          attachmentCallbacks: _attachmentCallbacks,
                          onRetryMessage: _retryMessage,
                        );
                      },
                    ),
                  ),
                ),
                ConversationComposer(
                  controller: _composer,
                  sending: _sending,
                  placeholder: l.chatComposerPlaceholder,
                  sendLabel: l.chatSendLabel,
                  onSend: _send,
                  attachLabel: l.chatAttachLabel,
                  onAttach: _sendAttachment,
                  onAttachmentPickError: _onAttachmentPickError,
                  voiceRecordLabel: l.voiceRecordLabel,
                  voiceDiscardLabel: l.voiceDiscardLabel,
                  voiceStopLabel: l.voiceStopLabel,
                  voicePlayLabel: l.voicePlayLabel,
                  voiceSendLabel: l.voiceSendLabel,
                  onSendVoice: _sendVoice,
                  onVoiceError: _onVoiceError,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    l.chatCryptoFooter,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
           if (_showPeerStatus)
             Positioned.fill(
               child: PeerStatusDrawer(
                 session: sessionForDrawer,
                 error: errorForDrawer,
                 refreshing: false,
                 onRefresh: () =>
                     ref.invalidate(activeSessionProvider(widget.sessionId)),
                 onClose: () => setState(() => _showPeerStatus = false),
               ),
             ),
            // Voice-call modals/overlay -- watches the per-session snapshot
            // and routes IncomingCallModal/OutgoingCallModal/CallOverlay
            // through showDialog based on pendingCall/outgoingCall/activeCall
            // (1-в-1 with React private-dm-screen.tsx L459-513). The layer
            // renders nothing itself; it only shows dialogs.
            Positioned.fill(
              child: VoiceCallLayer(
                sessionId: widget.sessionId,
                l: l,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state for a chat with no messages yet (React DmChatList empty
/// branch; chatEmptyTitle + chatEmptyBody).
class _Empty extends StatelessWidget {
  const _Empty({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.chatEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l.chatEmptyBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// One DM message row (React `DmMessageRow`): avatar (or a spacer when
/// grouped) + body column; non-grouped rows open with a sender-meta row.
/// Bubble (own/peer color + maxWidth 360), delivery ticks on own rows, and
/// the per-message AttachmentCard are in scope. Deferred: CallLogEntry, the
/// failed-message retry row (MlsBadge in the sender meta, [SenderMeta]).
