// S4.7: DM (direct message) screen for slice-one. Shows a session's
// message list + composer, mirroring the React ActiveDmChat
// (src/features/private-dm/ActiveChatPanes.tsx + MessageLists.tsx +
// ChatComposer.tsx): an app bar with the peer display name, a scrolling
// message list (own vs peer by alignment/color, distinguishing own via
// `fromDevice == snapshot.displayName`, the same rule the React app uses
// for `from_device === ownDeviceName`), a composer (TextField + Send), and
// a crypto footer line.
//
// Server/async state lives behind activeSessionProvider (FutureProvider.family
// of SessionSnapshot, ADR 0010). On send we call gateway.sendMessage via the
// gatewayProvider seam (ADR 0013) and invalidate the family entry so the new
// message re-renders. Only the text controller + send-in-flight flag are
// widget-local client state - hence ConsumerStatefulWidget. Polling choice
// for slice-one: refresh on init + after each send (no Timer.periodic loop);
// the React app polled every 1000ms, a full poll loop is a nice-to-have.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Direct-message screen for one session. Slice-one surface: message list +
/// composer. Own vs peer is inferred from `ChatMessage.fromDevice` vs the
/// session's own `displayName` (the same rule the React DmChatList applies
/// via `from_device === ownDeviceName`).
class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  final TextEditingController _composer = TextEditingController();
  bool _sending = false;

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
      // Re-fetch the session snapshot so the new message renders, and
      // refresh the list screen's cache so its row reflects the activity.
      ref.invalidate(activeSessionProvider(widget.sessionId));
      ref.invalidate(sessionListProvider);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    final title = async.maybeWhen(
      data: (s) => s.peerDisplayName.isEmpty ? s.sessionId : s.peerDisplayName,
      orElse: () => widget.sessionId,
    );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e.toString())),
                data: (s) => s.messages.isEmpty
                    ? _Empty(l: l)
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        reverse: true,
                        itemCount: s.messages.length,
                        itemBuilder: (context, i) {
                          // reverse=true displays newest at the bottom; index
                          // from the end so a send appends visually.
                          final msg = s.messages[s.messages.length - 1 - i];
                          final own = msg.fromDevice == s.displayName;
                          return _MessageBubble(message: msg, own: own);
                        },
                      ),
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
      ),
    );
  }
}

/// Empty-state for a chat with no messages yet (chatEmptyTitle + chatEmptyBody),
/// matching the React DmChatList's empty branch.
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

/// One message row. Own messages align right with a primary-tinted bubble;
/// peer messages align left with a surface-tinted bubble. Body text is
/// always shown; the delivery status renders as a small tick on own rows,
/// matching the React DeliveryTicks behavior for sent/delivered/pending.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.own});

  final ChatMessage message;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        own ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final align = own ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final mainAxisAlignment =
        own ? MainAxisAlignment.end : MainAxisAlignment.start;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: align,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: align,
                children: [
                  Text(message.body),
                  if (own) _DeliveryTicks(status: message.deliveryStatus),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryTicks extends StatelessWidget {
  const _DeliveryTicks({required this.status});
  final MessageDeliveryStatus? status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      MessageDeliveryStatus.delivered => '\u2713\u2713',
      MessageDeliveryStatus.sent => '\u2713',
      MessageDeliveryStatus.pending => '\u2026',
      MessageDeliveryStatus.failed || null => null,
    };
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
    );
  }
}