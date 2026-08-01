// S5-x: GroupScreen route shell -- the minimal, reachable surface for a
// private group. Mirrors ChannelScreen (S5-1) surface-by-surface: AppBar
// (group label + leave IconButton) + a scrolling message list (own vs
// others by FINGERPRINT, not display name -- groups are multi-party so
// names are not unique) + a composer. SHELL ONLY.
//
// Deferred to later atomics (matching how ChannelScreen / DmScreen layered
// polish later):
//   - sender-meta grouping (the 5-min window).
//   - ConversationTools search/filter.
//   - attachments (AttachmentCard + download/cancel seam).
//   - peer-status drawer (PeerStatusDrawer).
//   - admin badge / member-count subtitle / MLS-state subtitle (the rail
//     already shows admin crown + member count; the screen shell does not).
//   - copy-invite.
//   - public/encryption notice banner.
//   - the failed-message retry row.
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


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/routing/app_router.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(groupSnapshotProvider(widget.groupId));
    final groupForDrawer = async.value;
    final errorForDrawer = async.hasError ? async.error.toString() : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(async.maybeWhen(
          data: (group) => group.label ?? l.groupUntitled,
          orElse: () => widget.groupId,
        )),
        actions: [
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
                Expanded(
                  child: async.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(e.toString())),
                    data: (group) {
                      if (group.messages.isEmpty) {
                        return const _Empty();
                      }
                      return _GroupMessageListView(
                        messages: group.messages,
                        ownFingerprint: group.deviceFingerprint,
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
/// (mirrors ChannelScreen's `_ChannelMessageListView`); no grouping yet
/// (shell only).
class _GroupMessageListView extends StatelessWidget {
  const _GroupMessageListView({
    required this.messages,
    required this.ownFingerprint,
  });

  final List<GroupMessage> messages;
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
        return _GroupMessageRow(
          message: msg,
          ownFingerprint: ownFingerprint,
        );
      },
    );
  }
}

/// One group message row (React `GroupMessageRow`, shell form). Own =
/// `fromFingerprint == ownFingerprint` (fingerprint comparison, NOT display
/// name -- groups are multi-party). For others, a small `fromDevice` label
/// + a shortened `fromFingerprint` (monospace) sit above the body so senders
/// are distinguishable. Own aligns right with a primaryContainer bubble;
/// others align left with a surfaceContainerHighest bubble. No avatar,
/// grouping, or sender-meta widget yet.
class _GroupMessageRow extends StatelessWidget {
  const _GroupMessageRow({
    required this.message,
    required this.ownFingerprint,
  });

  final GroupMessage message;
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