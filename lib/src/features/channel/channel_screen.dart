// S5-1: ChannelScreen route shell -- the minimal, reachable surface for a
// public channel. Mirrors how DmScreen (S4.7) was built surface-by-surface:
// AppBar (channel name + leave IconButton) + a scrolling message list (own
// vs others by FINGERPRINT, not display name -- channels are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// Deferred to later atomics (matching how DmScreen layered polish later):
//   - sender-meta grouping (the 5-min window) -- DmScreen's groupDmMessages.
//   - ConversationTools search/filter -- DmScreen's filterDmMessages.
//   - attachments (AttachmentCard + download/cancel seam).
//   - peer-status drawer (PeerStatusDrawer) -- WIRED in this atomic.
//   - fingerprint badge (FingerprintBadge).
//   - the public-channel notice banner (React shows a PublicNotice for
//     plaintext channels; the shell has NO footer at all, unlike DmScreen's
//     chatCryptoFooter).
//   - the failed-message retry row.
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
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/util/format.dart' show shorten;

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
                Expanded(
                  child: async.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(e.toString())),
                    data: (snapshot) {
                      if (snapshot.messages.isEmpty) {
                        return const _Empty();
                      }
                      return _ChannelMessageListView(
                        messages: snapshot.messages,
                        ownFingerprint: snapshot.deviceFingerprint,
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
/// (mirrors DmScreen's `_MessageListView`); no grouping yet (shell only).
class _ChannelMessageListView extends StatelessWidget {
  const _ChannelMessageListView({
    required this.messages,
    required this.ownFingerprint,
  });

  final List<ChannelMessage> messages;
  final String ownFingerprint;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, i) {
        // newest -> oldest with reverse=true, so index the reversed list.
        final msg = messages[messages.length - 1 - i];
        return _ChannelMessageRow(
          message: msg,
          ownFingerprint: ownFingerprint,
        );
      },
    );
  }
}

/// One channel message row (React `ChannelMessageRow`, shell form). Own =
/// `fromFingerprint == ownFingerprint` (fingerprint comparison, NOT display
/// name -- channels are multi-party). For others, a small `fromDevice` label
/// + a shortened `fromFingerprint` (monospace) sit above the body so senders
/// are distinguishable. Own aligns right with a primaryContainer bubble;
/// others align left with a surfaceContainerHighest bubble. No avatar,
/// grouping, or sender-meta widget yet.
class _ChannelMessageRow extends StatelessWidget {
  const _ChannelMessageRow({
    required this.message,
    required this.ownFingerprint,
  });

  final ChannelMessage message;
  final String ownFingerprint;

  @override
  Widget build(BuildContext context) {
    final own = message.fromFingerprint == ownFingerprint;
    final theme = Theme.of(context);
    final bubble = own
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final alignment =
        own ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bubble,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: alignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!own) ...[
                Text(
                  message.fromDevice,
                  style: theme.textTheme.labelSmall,
                ),
                Text(
                  shorten(message.fromFingerprint, 6),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(message.body),
            ],
          ),
        ),
      ),
    );
  }
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
