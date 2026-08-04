part of 'dm_screen.dart';

mixin DmScreenActions on ConsumerState<DmScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _sending = false;
  int _transferOperations = 0;

  bool get _transferBusy => _transferOperations > 0;

  Future<T> _runTransfer<T>(Future<T> Function() operation) async {
    if (mounted) setState(() => _transferOperations++);
    try {
      return await operation();
    } finally {
      if (mounted) {
        setState(() {
          if (_transferOperations > 0) _transferOperations--;
        });
      }
    }
  }

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
      await _runTransfer(() => sendChatAttachment(
        gateway: ref.read(gatewayProvider),
        target: _target,
        fileName: attachment.fileName,
        mime: attachment.mime,
        dataBase64: attachment.dataBase64,
        thumbnailBase64: attachment.thumbnailBase64,
      ));
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
        busy: _transferBusy,
        onDownload: (id) => unawaited(_runTransfer(() =>
            downloadChatAttachment(
          gateway: _gateway,
          target: _target,
          attachmentId: id,
        ).then((_) => ref.invalidate(activeSessionProvider(_sessionId))))),
        onCancel: (id) => unawaited(_runTransfer(() => cancelChatAttachment(
          gateway: _gateway,
          target: _target,
          attachmentId: id,
        ).then((_) => ref.invalidate(activeSessionProvider(_sessionId))))),
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
      unawaited(_runTransfer(() => downloadChatAttachment(
        gateway: _gateway,
        target: _target,
        attachmentId: descriptor.attachmentId,
      ).then((_) => ref.invalidate(activeSessionProvider(_sessionId)))));
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
}
