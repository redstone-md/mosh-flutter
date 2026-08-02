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
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/channel/channel_message_row.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/dm/conversation_composer.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/crypto_notice_banner.dart';
import 'package:mosh/src/features/shared/chat_actions.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor;
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

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
  // The sealed [ChatTarget] for this channel -- routes the screen's
  // send/retry/attachment/leave dispatch through `chat_actions.dart` (the
  // shared DM/channel/group seam, Gap 4) so the gateway method name is
  // decided once here instead of triplicated across the three screens.
  late final ChatTarget _target = ChannelTarget(widget.name);
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive [filterChannelMessages] before grouping, mirroring
  // DmScreen's `_search` / `_filter` (filter-then-group order).
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;

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
      await sendChatText(
        gateway: ref.read(gatewayProvider),
        target: _target,
        body: body,
      );
      _composer.clear();
      ref.invalidate(channelSnapshotProvider(widget.name));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
  _AttachmentCallbacks _attachmentCallbacks(AttachmentView? view) =>
      _AttachmentCallbacks(
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
        onOpen: (descriptor) => _openAttachment(view),
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

  /// Opens the attachment's local file (React `openPath(local_path)` via the
  /// Tauri opener plugin -- here client-side, no Rust fn). Windows:
  /// `cmd /c start ""`; non-Windows is a no-op (the card disables Open when
  /// `view.localPath` is null; React `disabled={!view?.local_path}`).
  void _openAttachment(AttachmentView? view) {
    final localPath = view?.localPath;
    if (localPath == null || localPath.isEmpty || !Platform.isWindows) return;
    unawaited(Process.run('cmd', ['/c', 'start', '', '', localPath]));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(channelSnapshotProvider(widget.name));
    final channelForDrawer = async.value;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
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
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                CryptoNoticeBanner(
                  // React `PublicNotice` (ActiveChatPanes.tsx ~L434-445):
                  // `crypto-banner crypto-banner-public` with `IconHash`.
                  // Material `Icons.tag` is the closest hash glyph; the
                  // info-blue accent mirrors React's
                  // `.crypto-banner-public` border / `.crypto-icon` tint
                  // (rgba(108,183,232,*)).
                  icon: Icons.tag,
                  title: l.channelNoticeTitle,
                  body: l.channelNoticeBody,
                  accent: const Color(0xFF6CB7E8),
                ),
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
                    data: (snapshot) {
                      if (snapshot.messages.isEmpty) {
                        return const _Empty();
                      }
                      // React's filter-THEN-group order (MessageLists.tsx
                      // `ChannelChatList`): filter the raw list, THEN group
                      // the visible set so the 5-min window is computed
                      // across what the user actually sees. Empty-after-
                      // filter renders the shared `DmSearchEmpty` (the
                      // React `SearchEmpty` branch), mirroring DmScreen.
                      final filtered = filterChannelMessages(
                        snapshot.messages,
                        _search,
                        _filter,
                      );
                      if (filtered.isEmpty) {
                        return DmSearchEmpty(filter: _filter, l: l);
                      }
                      return _ChannelMessageListView(
                        messages: filtered,
                        ownFingerprint: snapshot.deviceFingerprint,
                        attachments: snapshot.attachments,
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
                  voiceRecordLabel: l.voiceRecordLabel,
                  voiceDiscardLabel: l.voiceDiscardLabel,
                  voiceStopLabel: l.voiceStopLabel,
                  voicePlayLabel: l.voicePlayLabel,
                  voiceSendLabel: l.voiceSendLabel,
                  onSendVoice: _sendVoice,
                  onVoiceError: _onVoiceError,
                ),
              ],
            ),
            if (_showPeerStatus)
              Positioned.fill(
                child: PeerStatusDrawer(
                  channel: channelForDrawer,
                  error: errorForDrawer,
                  refreshing: false,
                  onRefresh: () =>
                      ref.invalidate(channelSnapshotProvider(widget.name)),
                  onClose: () => setState(() => _showPeerStatus = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Message list view. `reverse: true` keeps the newest message at the bottom
/// (mirrors DmScreen's `_MessageListView`); grouping via
/// [groupChannelMessages] (the 5-min, same-`fromFingerprint` rule ported
/// from React `messageItems`/`shouldGroup`) so only the first row of a
/// group renders the sender meta. Rows are [ChannelMessageRow] instances
/// from `channel_message_row.dart`.
class _ChannelMessageListView extends StatelessWidget {
  const _ChannelMessageListView({
    required this.messages,
    required this.ownFingerprint,
    required this.attachments,
    required this.attachmentCallbacks,
    required this.onRetryMessage,
  });

  final List<ChannelMessage> messages;
  final String ownFingerprint;
  final List<AttachmentView> attachments;

  /// Per-row transfer-action callbacks (download/cancel/open). Built by the
  /// screen from the Gateway seam + invalidate + open (mirrors DmScreen's
  /// `_attachmentCallbacks`).
  final _AttachmentCallbacks Function(AttachmentView? view) attachmentCallbacks;

  /// Retry a failed outbound message by its messageId (React
  /// `retryChannelMessage`). Fire-and-forget via `unawaited` then
  /// invalidate the channel snapshot; the screen builds this from the
  /// Gateway seam.
  final void Function(String messageId) onRetryMessage;

  @override
  Widget build(BuildContext context) {
    // Chronological grouping (oldest -> newest), then reversed for the
    // reverse=true ListView (newest at the bottom). Mirrors DmScreen.
    final grouped = groupChannelMessages(messages).reversed.toList();
    final l = AppLocalizations.of(context)!;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      reverse: true,
      itemCount: grouped.length,
      itemBuilder: (context, i) {
        final item = grouped[i];
        final msg = item.message;
        // React parity: `view = attachments.views.get(attachment_id)` --
        // a per-message lookup into the snapshot's attachment views. The
        // DM port uses a linear scan (session lists are small); we mirror
        // that idiom exactly (see DmScreen's `_findAttachmentView`).
        final attachmentView = msg.attachment == null
            ? null
            : _findChannelAttachmentView(
                attachments, msg.attachment!.attachmentId);
        final callbacks = attachmentCallbacks(attachmentView);
        return ChannelMessageRow(
          message: msg,
          ownFingerprint: ownFingerprint,
          grouped: item.grouped,
          attachmentView: attachmentView,
          l: l,
          onAttachmentDownload: callbacks.onDownload,
          onAttachmentCancel: callbacks.onCancel,
          onAttachmentOpen: callbacks.onOpen,
          onRetry: onRetryMessage,
        );
      },
    );
  }
}

/// Linear lookup for the channel attachment view by id (mirrors DmScreen's
/// `_findAttachmentView` -- a channel's attachment list is small, so a plain
/// scan avoids a Map).
AttachmentView? _findChannelAttachmentView(
    List<AttachmentView> attachments, String attachmentId) {
  for (final v in attachments) {
    if (v.attachmentId == attachmentId) return v;
  }
  return null;
}

/// Per-row attachment transfer-action callbacks for the channel screen.
/// Mirrors DmScreen's `AttachmentCallbacks` value class (kept local to this
/// file to avoid coupling channel/group to the DM screen's class).
class _AttachmentCallbacks {
  const _AttachmentCallbacks({
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;
}

/// Empty-state for a channel with no messages yet. Shell form: no localized
/// title/body yet (deferred with the notice banner atomic); a plain hint so
/// the layout is not bare.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text(''));
  }
}
