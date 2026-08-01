// S5-1: ChannelScreen route shell -- the minimal, reachable surface for a
// public channel. Mirrors how DmScreen (S4.7) was built surface-by-surface:
// AppBar (channel name + leave IconButton) + a scrolling message list (own
// vs others by FINGERPRINT, not display name -- channels are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// Deferred to later atomics (matching how DmScreen layered polish later):
//   - sender-meta grouping (the 5-min window) -- DmScreen's groupDmMessages.
//   - attachments (AttachmentCard + download/cancel seam).
//   - peer-status drawer (PeerStatusDrawer) -- WIRED in this atomic.
//   - fingerprint badge (FingerprintBadge).
//   - the public-channel notice banner (React shows a PublicNotice for
//     plaintext channels; the shell has NO footer at all, unlike DmScreen's
//     chatCryptoFooter).
//   - the failed-message retry row.
//
// ConversationTools search/filter -- WIRED in this atomic: the screen owns
// `_search` / `_filter` widget-local state, renders `ConversationTools`
// above the list, and applies `filterChannelMessages` BEFORE
// `groupChannelMessages` (React's filter-then-group order), with the
// shared `DmSearchEmpty` branch when the filter hides every row.
//
// Own-vs-others rule (ported from React MessageLists.tsx ChannelChatList):
//   own = message.fromFingerprint == channel.deviceFingerprint
// Fingerprint comparison (NOT display name) is the key correctness point --
// channels are multi-party, so two members could share a display name but
// never a device fingerprint.
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

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/channel/channel_message_row.dart';
import 'package:mosh/src/features/shared/crypto_notice_banner.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView;
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
      await ref.read(gatewayProvider).sendChannel(
            name: widget.name,
            body: body,
          );
      _composer.clear();
      ref.invalidate(channelSnapshotProvider(widget.name));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _leave() async {
    await ref.read(gatewayProvider).leaveChannel(name: widget.name);
    if (!mounted) return;
    ref.invalidate(channelSnapshotProvider(widget.name));
    context.go(AppRoutes.sessions);
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
            onPressed: _leave,
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
  });

  final List<ChannelMessage> messages;
  final String ownFingerprint;
  final List<AttachmentView> attachments;

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
        return ChannelMessageRow(
          message: msg,
          ownFingerprint: ownFingerprint,
          grouped: item.grouped,
          attachmentView: attachmentView,
          l: l,
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

/// Composer: a TextField + a Send button, disabled while empty or sending.
/// Mirrors DmScreen's `_Composer` (shell form, inlined here).
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
