// S5-x: GroupScreen route shell -- the minimal, reachable surface for a
// private group. Mirrors ChannelScreen (S5-1) surface-by-surface: AppBar
// (group label + leave IconButton) + a scrolling message list (own vs
// others by FINGERPRINT, not display name -- groups are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// Deferred to later atomics (matching how ChannelScreen / DmScreen layered
// polish later):
//   - sender-meta grouping (the 5-min window).
//   - attachments (AttachmentCard + download/cancel seam).
//   - peer-status drawer (PeerStatusDrawer).
//   - admin badge / member-count subtitle / MLS-state subtitle (the rail
//     already shows admin crown + member count; the screen shell does not).
//   - public/encryption notice banner.
//   - the failed-message retry row.
//
// ConversationTools search/filter -- WIRED in this atomic: the screen owns
// `_search` / `_filter` widget-local state, renders `ConversationTools`
// above the list, and applies `filterGroupMessages` BEFORE
// `groupGroupMessages` (React's filter-then-group order), with the
// shared `DmSearchEmpty` branch when the filter hides every row.
//
// Own-vs-others rule (ported from React, same as ChannelScreen):
//   own = message.fromFingerprint == group.deviceFingerprint
// Fingerprint comparison (NOT display name) is the key correctness point --
// groups are multi-party, so two members could share a display name but
// never a device fingerprint.
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

import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/group/group_message_row.dart';
import 'package:mosh/src/features/shared/crypto_notice_banner.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

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
  // Copy-invite ephemeral state (React inviteCopied/inviteCopyTimer ~L255-256);
  // reverts after 1600ms; React's useEffect([inviteUri]) reset is omitted (GroupScreen remounts per groupId, so state resets on cross-group nav).
  bool _inviteCopied = false;
  Timer? _inviteCopyTimer;
  // Ephemeral search + filter (React ConversationTools); widget-local per
  // ADR 0010; drive [filterGroupMessages] before grouping, mirroring
  // DmScreen's `_search` / `_filter` (filter-then-group order).
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;

  @override
  void dispose() {
    _inviteCopyTimer?.cancel();
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

  Future<void> _copyInvite(String? inviteUri) async {
    if (inviteUri == null) return;
    await Clipboard.setData(ClipboardData(text: inviteUri));
    if (!mounted) return;
    setState(() => _inviteCopied = true);
    _inviteCopyTimer?.cancel();
    _inviteCopyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _inviteCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(groupSnapshotProvider(widget.groupId));
    final groupForDrawer = async.value;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: AppBar(
        // React ActiveChatHeader `title` + `subtitle` (ActiveChatPanes.tsx
        // ~L305-313): title = the group label (or "Private group" fallback);
        // subtitle = is_admin ? `${adminBadge} · ` : ""
        //   + `${member_count} member${member_count === 1 ? "" : "s"} · MLS ${state}`.
        // This Flutter `AppBar` (3.44) has no `subtitle:` slot, so the
        // subtitle renders as the second line of a two-line `title:` Column
        // (the idiomatic Flutter AppBar-with-subtitle pattern). Admin prefix
        // (with the " · " separator) only when admin; member count with
        // English plural ("1 member" vs "N members", selected by
        // `memberCount == BigInt.one` to mirror React's `member_count === 1`);
        // then the " · MLS {state}" suffix via groupScreenMlsStateSuffix.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(async.maybeWhen(
              data: (group) => group.label ?? l.groupUntitled,
              orElse: () => widget.groupId,
            )),
            Text(
              async.maybeWhen(
                data: (group) => _groupSubtitle(group, l),
                orElse: () => '',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          // React `beforeSearchActions` slot (ActiveChatPanes.tsx ~L315-324):
          // the admin-pill badge (<span className="admin-pill
          // chat-desktop-only" title={adminBadge}><IconCrown size=14/>
          // <span>{adminBadge}</span></span>) shown only if is_admin. Placed
          // FIRST in `actions:` so it sits left of the peer-status + leave
          // IconButtons, mirroring React's beforeSearchActions position
          // (left of the search). `Icons.workspace_premium` is the closest
          // Material equivalent to lucide `IconCrown` (a crown medal) -- the
          // rail already uses the same icon for its admin crown
          // (group_rail_item.dart).
          if (async.maybeWhen(
            data: (group) => group.isAdmin,
            orElse: () => false,
          ))
            _AdminPill(label: l.groupAdminBadge),
          // React `beforeSearchActions` copy-invite button (~L327-337):
          // ghost icon button copying `invite_uri`, check ~1.6s then
          // revert; only when inviteUri != null; icon 14; tooltip done/invite.
          if (async.maybeWhen(
            data: (group) => group.inviteUri != null,
            orElse: () => false,
          ))
            IconButton(
              icon: Icon(_inviteCopied ? Icons.check : Icons.copy, size: 14),
              tooltip:
                  _inviteCopied ? l.groupCopyInviteDone : l.groupCopyInvite,
              onPressed: () => _copyInvite(async.value?.inviteUri),
            ),
          IconButton(
            icon: const Icon(Icons.electrical_services, size: 18),
            tooltip: l.openPeerStatus,
            onPressed: () => setState(() => _showPeerStatus = true),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.groupLeaveLabel,
            onPressed: _leave,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // React wires the group pane's `afterHeader` (ActiveChatPanes.tsx
                // L352-360) as `<><GroupNotice />{needs_rejoin ? <RejoinNeeded/>
                // : null}{orgAddPrompt ? <OrgAddMissing/> : null}</>`. This atomic
                // ports ONLY the `<GroupNotice />` banner itself; the `needs_rejoin`
                // error fragment (orgRejoinNeededTitle/Body) and the `orgAddPrompt`
                // admin-add fragment are separate features and live in the SAME
                // slot -- they must stack BELOW the banner here in a later atomic.
                // TODO(group-rejoin-fragment): render the needs_rejoin inline-error
                //   (orgRejoinNeededTitle + orgRejoinNeededBody) here when set.
                // TODO(group-org-add-fragment): render the orgAddPrompt admin-add
                //   row (orgAddMissing + orgMissingOne/Many) here when present.
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
  });

  final List<GroupMessage> messages;
  final String ownFingerprint;
  final List<AttachmentView> attachments;

  @override
  Widget build(BuildContext context) {
    // Chronological grouping (oldest -> newest), then reversed for the
    // reverse=true ListView (newest at the bottom). Mirrors ChannelScreen.
    final grouped = groupGroupMessages(messages).reversed.toList();
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
        return GroupMessageRow(
          message: msg,
          ownFingerprint: ownFingerprint,
          grouped: item.grouped,
          attachmentView: attachmentView,
          // TODO(channel-group-attachment-transfer): wire to Gateway
          // download/cancel/open once the channel/group attachment-
          // transfer seam exists. No-op stubs for the display-only stage
          // (mirrors the DM port's `b7660f8`).
          onAttachmentDownload: (_) {},
          onAttachmentCancel: (_) {},
          onAttachmentOpen: (_) {},
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

/// Builds the GroupScreen AppBar subtitle, 1-в-1 with React
/// `ActiveChatHeader.subtitle` (ActiveChatPanes.tsx ~L308-313):
///   is_admin ? `${adminBadge} · ` : ""
///   + `${member_count} member${member_count === 1 ? "" : "s"} · MLS ${state}`
/// Admin prefix (with the " · " separator) only when admin; the member
/// count with English plural ("1 member" vs "N members", selected by
/// `memberCount == BigInt.one` to mirror React's `member_count === 1`);
/// then the " · MLS {state}" suffix from
/// [AppLocalizations.groupScreenMlsStateSuffix].
String _groupSubtitle(GroupSnapshot group, AppLocalizations l) {
  final n = group.memberCount.toInt();
  final memberPart = group.memberCount == BigInt.one
      ? l.membersCountSingular(n)
      : l.membersCount(n);
  final adminPrefix = group.isAdmin ? '${l.groupAdminBadge} · ' : '';
  return '$adminPrefix$memberPart${l.groupScreenMlsStateSuffix(group.state)}';
}

/// Admin-pill badge for the GroupScreen AppBar `actions:` slot, 1-в-1 with
/// React's `beforeSearchActions` admin-pill (ActiveChatPanes.tsx ~L315-324):
/// `<span className="admin-pill chat-desktop-only" title={adminBadge}>
/// `<IconCrown size=14/><span>{adminBadge}</span></span>`. A small pill with
/// a crown icon + the "admin" label, wrapped in a [Tooltip] that mirrors
/// React's `title` attribute. `Icons.workspace_premium` is the closest
/// Material equivalent to lucide `IconCrown` (a crown medal) -- the rail
/// already uses the same icon for its admin crown (group_rail_item.dart).
class _AdminPill extends StatelessWidget {
  const _AdminPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium, size: 14),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
