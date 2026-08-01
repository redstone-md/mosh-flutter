// S5-x: GroupScreen route shell -- the minimal, reachable surface for a
// private group. Mirrors ChannelScreen (S5-1) surface-by-surface: AppBar
// (group label + leave IconButton) + a scrolling message list (own vs
// others by FINGERPRINT, not display name -- groups are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// 1-в-1 with the React group pane (ActiveChatPanes.tsx ActiveGroupChat):
// AppBar (group label + admin-pill + copy-invite + leave via
// [GroupScreenHeader]) + GroupNotice banner + ConversationTools +
// message list (own vs others by FINGERPRINT) + composer + peer-status
// drawer overlay. The admin badge / member-count subtitle / MLS-state
// subtitle render in [GroupScreenHeader] (group_screen_header.dart).
//
// Deferred (slice-3 Rust Gateway seam): attachment/voice SENDING
// (AttachmentPicker + ChatComposer ChatDropZone/onSendVoice) and the
// attachment download/cancel transfer seam. AttachmentCard DISPLAY of an
// already-received attachment is ported (group_message_row.dart).
//
// Own-vs-others rule (React MessageLists.tsx GroupChatList, same as
// ChannelScreen): own = message.fromFingerprint == group.deviceFingerprint.
// Fingerprint comparison (NOT display name) is the key correctness point --
// groups are multi-party, so two members could share a display name but
// never a device fingerprint. Sender-meta grouping (5-min,
// same-fingerprint) + MultiPartySenderMeta render in group_message_row.dart.
//
// ConversationTools search/filter is widget-local (`_search` / `_filter`);
// the screen applies `filterGroupMessages` BEFORE `groupGroupMessages`
// (React's filter-then-group order) with the shared `DmSearchEmpty` branch
// when the filter hides every row.
//
// Key differences from ChannelScreen (groups vs channels):
//   - keyed by `groupId` (the identity), NOT `name`.
//   - title = `group.label ?? l.groupUntitled` (label is nullable; React
//     falls back to `groupText.untitled` = "Private group").
//   - leave via `gateway.closeGroup` (group teardown is frb `close` ->
//     Gateway `closeGroup`; channel used `leaveChannel`).
//   - send via `gateway.sendGroup` (NOT `sendChannel`); then
//     `ref.invalidate(groupSnapshotProvider(widget.groupId))`.
//
// Server state: groupSnapshotProvider (ADR 0010); send calls
// gateway.sendGroup via gatewayProvider (ADR 0013) then invalidates the
// family entry; leave calls gateway.closeGroup then navigates back to the
// sessions list. The composer is widget-local (ConsumerStatefulWidget).
// Peer-status drawer: mirrors DmScreen wiring. The drawer (PeerStatusDrawer,
// shared with the DM + Channel screens) branches internally -- session ->
// channel -> group -> NoActiveSession -- and is rendered here with
// group: set so it shows GroupDiagnostics. An AppBar action toggles
// _showPeerStatus; the body is a Stack whose last child is a
// Positioned.fill(PeerStatusDrawer(...)) overlay.
//
// The AppBar (title Column + admin-pill + copy-invite + peer-status + leave
// actions) and its copy-invite ephemeral state live in [GroupScreenHeader]
// (group_screen_header.dart), extracted to restore the 500-line headroom;
// this screen passes `groupId` + the `onOpenPeerStatus` / `onLeave`
// callbacks. The body (notice banner + ConversationTools + message list +
// composer + peer-status drawer overlay) stays here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';
import 'dart:io';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/group/group_message_row.dart';
import 'package:mosh/src/features/group/group_screen_header.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/crypto_notice_banner.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/util/format.dart' show shorten;

/// Group screen for one private group. Own vs others is inferred from
/// `GroupMessage.fromFingerprint` vs the group's `deviceFingerprint`
/// (React's `from_fingerprint === group.device_fingerprint` rule -- NOT
/// display name, since groups are multi-party). Keyed by `groupId` (the
/// group identity), not a display name.
class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _sending = false;
  bool _showPeerStatus = false;
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive [filterGroupMessages] before grouping, mirroring
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
      await ref.read(gatewayProvider).sendGroup(
            groupId: widget.groupId,
            body: body,
          );
      _composer.clear();
      ref.invalidate(groupSnapshotProvider(widget.groupId));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _leave() async {
    await ref.read(gatewayProvider).closeGroup(groupId: widget.groupId);
    if (!mounted) return;
    ref.invalidate(groupSnapshotProvider(widget.groupId));
    context.go(AppRoutes.sessions);
  }

  // Close-flow confirmation -- 1-в-1 with React `useChatCloseFlow` group
  // branch (use-chat-close-flow.ts L67-77): the leave action opens a
  // ConfirmDialog with `Leave ${label}?` / body / `Leave group` before the
  // real `_leave` runs. React's `label = group?.label ?? (group ?
  // shorten(group.group_id, 6) : "this group")`; the group screen always
  // has a resolved group (it is the active screen), so the fallback is
  // `group.label ?? shorten(group.groupId, 6)`. If the snapshot is still
  // pending when the user taps leave, fall back to `shorten(groupId, 6)`
  // (the widget arg), which mirrors the resolved-group fallback shape.
  Future<void> _requestLeave() async {
    final l = AppLocalizations.of(context)!;
    final group =
        ref.read(groupSnapshotProvider(widget.groupId)).value;
    final label = group?.label ?? shorten(group?.groupId ?? widget.groupId, 6);
    final confirmed = await showConfirmDialog(
      context: context,
      title: l.leaveGroupTitle(label),
      body: l.leaveGroupBody,
      confirmLabel: l.leaveGroupConfirm,
      cancelLabel: l.dialogCancel,
    );
    if (confirmed) await _leave();
  }

  /// Builds the per-row transfer-action callbacks for [GroupMessageRow]'s
  /// AttachmentCard: download/cancel fire the Gateway seam then invalidate
  /// the group snapshot so the next poll re-renders state + progress
  /// (fire-and-forget via `unawaited`, mirrors DmScreen's
  /// `_attachmentCallbacks` and ChannelScreen's mirror).
  _AttachmentCallbacks _attachmentCallbacks(AttachmentView? view) =>
      _AttachmentCallbacks(
        onDownload: (id) => unawaited(ref
            .read(gatewayProvider)
            .downloadGroupAttachment(groupId: widget.groupId, attachmentId: id)
            .then((_) => ref.invalidate(groupSnapshotProvider(widget.groupId)))),
        onCancel: (id) => unawaited(ref
            .read(gatewayProvider)
            .cancelGroupAttachment(groupId: widget.groupId, attachmentId: id)
            .then((_) => ref.invalidate(groupSnapshotProvider(widget.groupId)))),
        onOpen: (descriptor) => _openAttachment(view),
      );

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
    final async = ref.watch(groupSnapshotProvider(widget.groupId));
    final groupForDrawer = async.value;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: GroupScreenHeader(
        groupId: widget.groupId,
        onOpenPeerStatus: () => setState(() => _showPeerStatus = true),
        onLeave: _requestLeave,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // React wires the group pane's `afterHeader` (ActiveChatPanes.tsx
                // L352-380) as `<><GroupNotice />{needs_rejoin ? <RejoinNeeded/>
                // : null}{orgAddPrompt ? <OrgAddMissing/> : null}</>`. This atomic
                // ports the `<GroupNotice />` banner (crypto_notice_banner.dart)
                // AND the `needs_rejoin` inline-error fragment; the `orgAddPrompt`
                // admin-add fragment stays deferred (separate atomic -- needs an
                // org-roster Gateway seam that does not exist in Flutter yet).
                // TODO(group-org-add-prompt): render the orgAddPrompt admin-add
                //   row (orgAddMissing + orgMissingOne/Many) here when present.
                //   Deferred: requires `count`/`busy`/`onAdd` props sourced from
                //   an org-roster Gateway provider that does not exist in Flutter
                //   yet (needs Rust + Gateway work in a later atomic). The
                //   needs_rejoin inline-error below is DONE (this atomic).
                CryptoNoticeBanner(
                  // React `GroupNotice` (ActiveChatPanes.tsx ~L420-432):
                  // `crypto-banner crypto-banner-group` with `IconLock`.
                  // Material `Icons.lock` mirrors lucide `IconLock`; the
                  // moss-green accent mirrors React's
                  // `.crypto-banner-group` border / `.crypto-icon` tint
                  // (rgba(183,216,74,*), var(--moss-glow)).
                  icon: Icons.lock,
                  title: l.groupNoticeTitle,
                  body: l.groupNoticeBody,
                  accent: const Color(0xFFB7D84A),
                ),
                // React `needs_rejoin` fragment (ActiveChatPanes.tsx L355-360):
                // `<div className="inline-error" role="alert"><strong>
                // {rejoinNeededTitle}.</strong> {" "}{rejoinNeededBody}</div>`.
                // Reads `group.needsRejoin` off the snapshot; renders ONLY when
                // the snapshot is resolved AND the flag is true (loading/error
                // => no banner). Stacks BELOW the GroupNotice, ABOVE
                // ConversationTools -- matching React's afterHeader order.
                if (_needsRejoin(async))
                  _RejoinNeededError(
                    title: l.orgRejoinNeededTitle,
                    body: l.orgRejoinNeededBody,
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
                    data: (group) {
                      if (group.messages.isEmpty) {
                        return const _Empty();
                      }
                      // React's filter-THEN-group order (MessageLists.tsx
                      // `GroupChatList`): filter the raw list, THEN group
                      // the visible set so the 5-min window is computed
                      // across what the user actually sees. Empty-after-
                      // filter renders the shared `DmSearchEmpty` (the
                      // React `SearchEmpty` branch), mirroring DmScreen.
                      final filtered = filterGroupMessages(
                        group.messages,
                        _search,
                        _filter,
                      );
                      if (filtered.isEmpty) {
                        return DmSearchEmpty(filter: _filter, l: l);
                      }
                      return _GroupMessageListView(
                        messages: filtered,
                        ownFingerprint: group.deviceFingerprint,
                        attachments: group.attachments,
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
              ],
            ),
            if (_showPeerStatus)
              Positioned.fill(
                child: PeerStatusDrawer(
                  group: groupForDrawer,
                  error: errorForDrawer,
                  refreshing: false,
                  onRefresh: () =>
                      ref.invalidate(groupSnapshotProvider(widget.groupId)),
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
/// (mirrors ChannelScreen's `_ChannelMessageListView`); grouping via
/// [groupGroupMessages] (the 5-min, same-`fromFingerprint` rule ported
/// from React `messageItems`/`shouldGroup`) so only the first row of a
/// group renders the sender meta. Rows are [GroupMessageRow] instances
/// from `group_message_row.dart`.
class _GroupMessageListView extends StatelessWidget {
  const _GroupMessageListView({
    required this.messages,
    required this.ownFingerprint,
    required this.attachments,
    required this.attachmentCallbacks,
  });

  final List<GroupMessage> messages;
  final String ownFingerprint;
  final List<AttachmentView> attachments;
  /// Per-row transfer-action callbacks (download/cancel/open). Built by the
  /// screen from the Gateway seam + invalidate + open (mirrors DmScreen's
  /// `_attachmentCallbacks`).
  final _AttachmentCallbacks Function(AttachmentView? view) attachmentCallbacks;

  @override
  Widget build(BuildContext context) {
    // Chronological grouping (oldest -> newest), then reversed for the
    // reverse=true ListView (newest at the bottom). Mirrors ChannelScreen.
    final grouped = groupGroupMessages(messages).reversed.toList();
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
            : _findGroupAttachmentView(
                attachments, msg.attachment!.attachmentId);
        final callbacks = attachmentCallbacks(attachmentView);
        return GroupMessageRow(
          message: msg,
          ownFingerprint: ownFingerprint,
          grouped: item.grouped,
          attachmentView: attachmentView,
          l: l,
          onAttachmentDownload: callbacks.onDownload,
          onAttachmentCancel: callbacks.onCancel,
          onAttachmentOpen: callbacks.onOpen,
        );
      },
    );
  }
}

/// Linear lookup for the group attachment view by id (mirrors DmScreen's
/// `_findAttachmentView` -- a group's attachment list is small, so a plain
/// scan avoids a Map).
AttachmentView? _findGroupAttachmentView(
    List<AttachmentView> attachments, String attachmentId) {
  for (final v in attachments) {
    if (v.attachmentId == attachmentId) return v;
  }
  return null;
}

/// Per-row attachment transfer-action callbacks for the group screen.
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

/// Reads `group.needsRejoin` off the resolved [GroupSnapshot] for the
/// inline-error gate. Returns `false` while the snapshot is loading or in
/// error (no data) so the banner does not render until the group is known.
/// Mirrors React's `props.group.needs_rejoin` guard in ActiveChatPanes.tsx
/// (the snapshot is always resolved on the React side by the time the pane
/// renders; here the async path can still be pending).
bool _needsRejoin(AsyncValue<GroupSnapshot?> async) {
  final group = async.maybeWhen(data: (g) => g, orElse: () => null);
  return group != null && group.needsRejoin;
}

/// The `needs_rejoin` inline-error -- 1-в-1 with React's
/// `<div className="inline-error" role="alert">` fragment
/// (ActiveChatPanes.tsx L355-360). Structure: a red-tinted alert box holding
/// `<strong>{rejoinNeededTitle}.</strong>` (bold, with the period React
/// appends via `<strong>{title}.</strong>`) + a space + the body. The tint
/// mirrors React's `.inline-error` CSS (desktop-shell.css L1066-1073):
/// `padding: 10px 14px`, `border-radius: 10px`,
/// `background: rgba(232,106,90,0.08)`, `border: 1px solid rgba(232,106,90,0.35)`,
/// `color: var(--danger)`, `font-size: 12px`. Material's `colorScheme.error`
/// is the idiomatic Flutter equivalent of `--danger`, so the tint is derived
/// from it (8% bg, 35% border) to match React's rgba alphas.
///
/// Accessibility: React sets `role="alert"`. Flutter has no direct `alert`
/// role; `Semantics(liveRegion: true, container: true)` is the closest
/// equivalent -- a live region announces updates to assistive tech, which
/// is what an inline alert does. The whole box is one semantic node labeled
/// by the title + body so it reads as a single alert, not three nodes.
class _RejoinNeededError extends StatelessWidget {
  const _RejoinNeededError({required this.title, required this.body});

  /// The bold title line. React renders `<strong>{title}.</strong>` -- the
  /// period is appended by React, NOT in the ARB value ("Group out of sync"
  /// has no trailing period). We append `.` here in the bold span to match.
  final String title;

  /// The body paragraph (React `{rejoinNeededBody}`).
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $body',
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          // React `.inline-error`: rgba(232,106,90,0.08) bg +
          // 1px rgba(232,106,90,0.35) border + 10px radius.
          color: error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: error.withValues(alpha: 0.35), width: 1),
        ),
        child: Text.rich(
          // React: `<strong>{title}.</strong>{" "}{body}` -- bold title
          // (with appended period) + a literal space + the body, inline.
          TextSpan(
            children: [
              TextSpan(
                text: '$title.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: error,
                  fontSize: 12,
                ),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: error,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty-state for a group with no messages yet. Shell form: no localized
/// title/body yet (deferred with the notice banner atomic); a plain hint so
/// the layout is not bare.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text(''));
  }
}

/// Composer: a TextField + a Send button, disabled while empty or sending.
/// Mirrors ChannelScreen's `_Composer` (shell form, inlined here).
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
