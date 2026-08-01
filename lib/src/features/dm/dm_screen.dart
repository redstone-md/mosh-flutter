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
// Attachments (this atomic): each row wires an `AttachmentCard` via
// `_attachmentCallbacks` -- download/cancel hit the Gateway seam (99bc9d9),
// open runs the dart:io launcher (no Rust fn). Deferred: call events, the
// failed-message retry row, the full poll loop.
//
// Server state: activeSessionProvider (ADR 0010); send calls
// gateway.sendMessage via gatewayProvider (ADR 0013) and invalidates the
// family entry. Composer + search/filter + peer-status drawer are widget-
// local (ConsumerStatefulWidget). Slice-one: refresh on init + after send.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/attachment_card.dart';
import 'package:mosh/src/features/dm/dm_message_list.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/dm/conversation_composer.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/fingerprint_badge.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

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

  // Ephemeral confirmed-fingerprint set (React `confirmedFingerprints`
  // useState, use-chat-close-flow.ts). Widget-local per ADR 0010; purely
  // client-side, NOT a Gateway call. `_leave` removes the sessionId from
  // this set on close (mirrors React `confirmCloseActive`'s
  // `confirmedFingerprints.delete(target.id)` cleanup).
  Set<String> _confirmedFingerprints = {};

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(gatewayProvider).sendMessage(
            sessionId: widget.sessionId,
            body: body,
          );
      _composer.clear();
      ref.invalidate(activeSessionProvider(widget.sessionId));
      ref.invalidate(sessionListProvider);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
      await ref.read(gatewayProvider).sendPrivateAttachment(
            sessionId: widget.sessionId,
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
        onDownload: (id) => unawaited(_gateway
            .downloadAttachment(sessionId: _sessionId, attachmentId: id)
            .then((_) => ref.invalidate(activeSessionProvider(_sessionId)))),
        onCancel: (id) => unawaited(_gateway
            .cancelAttachment(sessionId: _sessionId, attachmentId: id)
            .then((_) => ref.invalidate(activeSessionProvider(_sessionId)))),
        onOpen: (descriptor) => _openAttachment(view),
      );

  /// Retry a failed outbound DM message (React `retryDmMessage`,
  /// native-messaging-gateway.ts; Rust `private_dm_retry_message`).
  /// Fire-and-forget via `unawaited`, then invalidate the session snapshot
  /// so the next poll re-renders the row's delivery status (mirrors the
  /// attachment download/cancel wiring + the channel/group retry seam).
  void _retryMessage(String messageId) {
    unawaited(_gateway
        .retryDmMessage(sessionId: _sessionId, messageId: messageId)
        .then((_) => ref.invalidate(activeSessionProvider(_sessionId))));
  }

  /// Opens the attachment's local file (React `openPath(local_path)` via
  /// the Tauri opener plugin -- here client-side, no Rust fn). Windows:
  /// `cmd /c start ""`; non-Windows is a TODO no-op (the card disables Open
  /// when `view.localPath` is null; React `disabled={!view?.local_path}`).
  void _openAttachment(AttachmentView? view) {
    final localPath = view?.localPath;
    if (localPath == null || localPath.isEmpty || !Platform.isWindows) return;
    unawaited(Process.run('cmd', ['/c', 'start', '', '', localPath]));
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
    await ref.read(gatewayProvider).closeSession(sessionId: widget.sessionId);
    if (!mounted) return;
    setState(() => _confirmedFingerprints = _confirmedFingerprints
      ..remove(widget.sessionId));
    ref.invalidate(activeSessionProvider(widget.sessionId));
    ref.invalidate(sessionListProvider);
    context.go(AppRoutes.sessions);
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
                ConversationTools(
                  search: _search,
                  filter: _filter,
                  onSearch: (value) => setState(() => _search = value),
                  onFilter: (value) => setState(() => _filter = value),
                  l: l,
                ),
                Expanded(
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
                ConversationComposer(
                  controller: _composer,
                  sending: _sending,
                  placeholder: l.chatComposerPlaceholder,
                  sendLabel: l.chatSendLabel,
                  onSend: _send,
                  attachLabel: l.chatAttachLabel,
                  onAttach: _sendAttachment,
                  onAttachmentPickError: _onAttachmentPickError,
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
