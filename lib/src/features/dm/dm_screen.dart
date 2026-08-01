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

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/attachment_card.dart';
import 'package:mosh/src/features/dm/dm_message_row.dart';
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/fingerprint_badge.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';

/// Grouping window ported 1-1 from React `GROUP_WINDOW_MS`
/// (src/features/private-dm/MessageLists.tsx): 5 minutes.
const Duration _groupWindow = Duration(minutes: 5);

/// One grouping row: the message plus whether it was grouped under the
/// previous visible message (React `messageItems`/`shouldGroup`).
@visibleForTesting
class GroupedMessage {
  const GroupedMessage({required this.message, required this.grouped});

  final ChatMessage message;
  final bool grouped;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupedMessage &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          grouped == other.grouped;

  @override
  int get hashCode => Object.hash(message, grouped);
}

/// Computes the per-message `grouped` flag (React `messageItems` /
/// `shouldGroup` in MessageLists.tsx). Chronological, oldest -> newest: the
/// first message is never grouped; a row groups when its `fromDevice`
/// equals the previous one AND both `sentAtMs` are non-null AND `current >=
/// previous` AND the delta is within [_groupWindow] (5 min). A null
/// `sentAtMs` breaks grouping (React's `!prev || !cur` guard); the screen
/// reverses the result for display (reverse=true).
@visibleForTesting
List<GroupedMessage> groupDmMessages(List<ChatMessage> messages) {
  final result = <GroupedMessage>[];
  for (var i = 0; i < messages.length; i++) {
    final current = messages[i];
    final grouped = i > 0 && _shouldGroup(messages[i - 1], current);
    result.add(GroupedMessage(message: current, grouped: grouped));
  }
  return result;
}

bool _shouldGroup(ChatMessage previous, ChatMessage current) {
  final prevMs = previous.sentAtMs;
  final curMs = current.sentAtMs;
  if (prevMs == null || curMs == null) return false;
  if (previous.fromDevice != current.fromDevice) return false;
  if (curMs < prevMs) return false;
  return curMs - prevMs <= BigInt.from(_groupWindow.inMilliseconds);
}

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
  // client-side, NOT a Gateway call. TODO: removal-on-close is a later
  // atomic (no close-session UI in DmScreen yet).
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

  /// Builds the per-row transfer-action callbacks for [AttachmentCard]:
  /// download/cancel fire the Gateway seam (99bc9d9) then invalidate the
  /// session provider so the next poll re-renders state + progress
  /// (fire-and-forget via `unawaited`).
  AttachmentCallbacks _attachmentCallbacks(AttachmentView? view) =>
      AttachmentCallbacks(
        onDownload: (id) => unawaited(_gateway
            .downloadAttachment(sessionId: _sessionId, attachmentId: id)
            .then((_) => ref.invalidate(activeSessionProvider(_sessionId)))),
        onCancel: (id) => unawaited(_gateway
            .cancelAttachment(sessionId: _sessionId, attachmentId: id)
            .then((_) => ref.invalidate(activeSessionProvider(_sessionId)))),
        onOpen: (descriptor) => _openAttachment(view),
      );

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

  void _confirmFingerprint() => setState(() => _confirmedFingerprints =
      {..._confirmedFingerprints, widget.sessionId});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    final title = async.maybeWhen(
      data: (s) => s.peerDisplayName.isEmpty ? s.sessionId : s.peerDisplayName,
      orElse: () => widget.sessionId,
    );
    final fingerprint = async.value?.fingerprint ?? '';
    final confirmed = fingerprint.isNotEmpty &&
        _confirmedFingerprints.contains(widget.sessionId);
    final sessionForDrawer = async.value;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          FingerprintBadge(fingerprint: fingerprint, confirmed: confirmed, onConfirm: _confirmFingerprint),
          IconButton(
            icon: const Icon(Icons.electrical_services, size: 18),
            tooltip: l.openPeerStatus,
            onPressed: () => setState(() => _showPeerStatus = true),
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
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(e.toString())),
                    data: (s) {
                      if (s.messages.isEmpty) return _Empty(l: l);
                      final filtered =
                          filterDmMessages(s.messages, _search, _filter);
                      if (filtered.isEmpty) {
                        return DmSearchEmpty(filter: _filter, l: l);
                      }
                      return _MessageListView(
                        ownDeviceName: s.displayName,
                        grouped: groupDmMessages(filtered).reversed.toList(),
                        attachments: s.attachments,
                        attachmentCallbacks: _attachmentCallbacks,
                      );
                    },
                  ),
                ),
                _Composer(
                  controller: _composer,
                  sending: _sending,
                  placeholder: l.chatComposerPlaceholder,
                  sendLabel: l.chatSendLabel,
                  onSend: _send,
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
                  onRefresh: () => ref
                      .invalidate(activeSessionProvider(widget.sessionId)),
                  onClose: () => setState(() => _showPeerStatus = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Message list view. `grouped` is in DISPLAY order (newest -> oldest);
/// the screen computes it chronologically via [groupDmMessages] then
/// reverses it.
class _MessageListView extends StatelessWidget {
  const _MessageListView({
    required this.grouped,
    required this.ownDeviceName,
    required this.attachments,
    required this.attachmentCallbacks,
  });

  final List<GroupedMessage> grouped;
  final String ownDeviceName;
  final List<AttachmentView> attachments;
  final AttachmentCallbacks Function(AttachmentView? view) attachmentCallbacks;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      reverse: true,
      itemCount: grouped.length,
      itemBuilder: (context, i) {
        final item = grouped[i];
        final msg = item.message;
        final own = msg.fromDevice == ownDeviceName;
        final attachmentView = msg.attachment == null
            ? null
            : _findAttachmentView(attachments, msg.attachment!.attachmentId);
        final callbacks = attachmentCallbacks(attachmentView);
        return DmMessageRow(
          message: msg,
          own: own,
          grouped: item.grouped,
          attachmentView: attachmentView,
          onAttachmentDownload: callbacks.onDownload,
          onAttachmentCancel: callbacks.onCancel,
          onAttachmentOpen: callbacks.onOpen,
        );
      },
    );
  }
}

/// Linear lookup for the attachment view by id (session lists are small --
/// one DM's files -- so a plain scan avoids a Map).
AttachmentView? _findAttachmentView(
    List<AttachmentView> attachments, String attachmentId) {
  for (final v in attachments) {
    if (v.attachmentId == attachmentId) return v;
  }
  return null;
}

/// Bundles the three transfer-action callbacks one card needs (React
/// `attachments.onDownload`/`onCancel`/`onOpen`); a class keeps the
/// `_MessageListView` field type short. Built per-row so Open resolves
/// THIS row's `view.localPath`.
class AttachmentCallbacks {
  const AttachmentCallbacks({
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;
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

/// Composer: a TextField + a Send button, disabled while empty or sending.
/// Mirrors the React Composer (disabled on `!value.trim() || sending`).
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.placeholder,
    required this.sendLabel,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final String placeholder;
  final String sendLabel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = !sending && controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final enabled = !sending && value.text.trim().isNotEmpty;
          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !sending,
                  onSubmitted: (_) {
                    if (canSend) onSend();
                  },
                  decoration: InputDecoration(
                    hintText: placeholder,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: enabled ? onSend : null,
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(sendLabel),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One DM message row (React `DmMessageRow`): avatar (or a spacer when
/// grouped) + body column; non-grouped rows open with a sender-meta row.
/// Bubble (own/peer color + maxWidth 360), delivery ticks on own rows, and
/// the per-message AttachmentCard are in scope. Deferred: CallLogEntry, the
/// failed-message retry row (MlsBadge in the sender meta, [SenderMeta]).
