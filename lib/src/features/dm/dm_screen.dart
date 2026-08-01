// S4.7: DM (direct message) screen for slice-one. Shows a session's
// message list + composer, mirroring the React ActiveDmChat
// (src/features/private-dm/ActiveChatPanes.tsx + MessageLists.tsx +
// ChatComposer.tsx): an app bar with the peer display name, a scrolling
// message list (own vs peer by alignment/color, distinguishing own via
// `fromDevice == snapshot.displayName`, the same rule the React app uses
// for `from_device === ownDeviceName`), a composer (TextField + Send), and
// a crypto footer line.
//
// Grouping + sender meta (this atomic): the message list now ports the
// React `DmMessageRow` grouping rule from MessageLists.tsx -- within a
// 5-minute window, consecutive messages from the same `fromDevice` are
// "grouped": only the first message in a group renders an avatar plus a
// sender-meta row (raw `fromDevice` name + HH:mm timestamp); grouped rows
// render an avatar-width spacer and omit the meta row. The grouping is
// computed in CHRONOLOGICAL order (oldest -> newest) so the window
// comparison is correct, then the list is reversed for display
// (reverse=true keeps the newest at the bottom). Deferred to later
// atomics (in-scope surface only): attachments (AttachmentCard), call
// events (CallLogEntry), the MLS badge (MlsBadge), and the failed-message
// retry row.
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

/// Grouping window ported 1-1 from React `GROUP_WINDOW_MS`
/// (src/features/private-dm/MessageLists.tsx): 5 minutes.
const Duration _groupWindow = Duration(minutes: 5);

/// Avatar diameter used by `_DmMessageRow` -- both the real `CircleAvatar`
/// and the grouped-row spacer share this width so a grouped row stays
/// visually indented under the first row's avatar (matching React's
/// `avatar avatar-spacer` element).
const double _avatarSize = 32;

/// One row of the grouping result: the underlying message plus whether it
/// was grouped under the previous visible message (per the React rule in
/// `messageItems`/`shouldGroup`).
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

/// Computes the per-message `grouped` flag for a DM message list, ported
/// 1-1 from the React `messageItems` + `shouldGroup` helpers in
/// `src/features/private-dm/MessageLists.tsx`.
///
/// Rule (chronological, oldest -> newest):
///   - the first message is never grouped;
///   - a message is grouped when its `fromDevice` equals the previous
///     message's `fromDevice` AND both `sentAtMs` are non-null AND
///     `current.sentAtMs >= previous.sentAtMs` AND the delta is within
///     [_groupWindow] (5 minutes).
///
/// A null `sentAtMs` always breaks grouping (a message with no timestamp
/// starts a new group), matching React's `!previous.sent_at_ms ||
/// !current.sent_at_ms` guard. The input order is treated as chronological;
/// the DM screen reverses the result for display (reverse=true).
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
  // BigInt is unsigned-only here; guard against a non-monotonic source by
  // comparing on the subtracted side exactly as React does
  // (`current.sent_at_ms >= previous.sent_at_ms`).
  if (curMs < prevMs) return false;
  return curMs - prevMs <= BigInt.from(_groupWindow.inMilliseconds);
}

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
                    : _MessageListView(
                        ownDeviceName: s.displayName,
                        grouped: groupDmMessages(s.messages).reversed.toList(),
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

/// Message list view extracted from the build body. `grouped` is already in
/// DISPLAY order (newest -> oldest, ready for reverse=true) -- the screen
/// computes it chronologically via [groupDmMessages] then reverses it
/// before passing it here so the window comparison stays correct.
class _MessageListView extends StatelessWidget {
  const _MessageListView({required this.grouped, required this.ownDeviceName});

  final List<GroupedMessage> grouped;
  final String ownDeviceName;

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
        return _DmMessageRow(
          message: msg,
          own: own,
          grouped: item.grouped,
        );
      },
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

/// One DM message row, mirroring the React `DmMessageRow`. Layout matches the
/// in-scope React surface: an avatar (or an avatar-width spacer when this
/// row is grouped under the previous message) followed by a body column.
/// For non-grouped rows the body column opens with a sender-meta row: the
/// raw `fromDevice` name in bold + a locale-agnostic HH:mm timestamp in a
/// muted style (React localizes the clock via `toLocaleTimeString`; HH:mm is
/// the slice-one equivalent, no new ARB key -- the device name is raw per
/// React). The bubble (own/peer color + alignment + maxWidth 360) and the
/// delivery ticks on own rows are unchanged from the prior `_MessageBubble`.
///
/// Deferred to later atomics: AttachmentCard, CallLogEntry, MlsBadge, and the
/// failed-message retry row -- the React `DmMessageRow` composes all of them,
/// but this atomic ports the grouping + sender meta only.
class _DmMessageRow extends StatelessWidget {
  const _DmMessageRow({
    required this.message,
    required this.own,
    required this.grouped,
  });

  final ChatMessage message;
  final bool own;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = own ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final align = own ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final mainAxisAlignment =
        own ? MainAxisAlignment.end : MainAxisAlignment.start;
    // The avatar sits on the peer's side (start for peer, end for own). When
    // grouped, the avatar slot becomes a width-only spacer so the body of
    // a grouped row stays indented under its group's first row -- matching
    // React's `avatar avatar-spacer`.
    final avatarSlot = grouped
        ? const SizedBox(width: _avatarSize)
        : CircleAvatar(
            backgroundColor: _avatarColor(message.fromDevice),
            maxRadius: _avatarSize / 2,
            child: Text(
              message.fromDevice.isEmpty
                  ? '?'
                  : message.fromDevice[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: align,
        children: [
          // For peer rows the avatar leads; for own rows the avatar trails.
          if (!own) avatarSlot,
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
                  if (!grouped) _SenderMeta(message: message),
                  Text(message.body),
                  if (own) _DeliveryTicks(status: message.deliveryStatus),
                ],
              ),
            ),
          ),
          if (own) avatarSlot,
        ],
      ),
    );
  }
}

/// Sender-meta row for the first message of a group: the raw `fromDevice`
/// name in bold + a muted locale-agnostic HH:mm timestamp. Mirrors the
/// non-grouped branch of React `DmMessageRow`'s `message-meta` row minus the
/// `MlsBadge` (deferred). The MLS badge is intentionally omitted here.
class _SenderMeta extends StatelessWidget {
  const _SenderMeta({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = _formatClock(message.sentAtMs);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              message.fromDevice,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (clock != null) ...[
            const SizedBox(width: 6),
            Text(
              clock,
              style:
                  theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
          ],
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

/// Locale-agnostic HH:mm clock for the sender-meta row. Returns null when
/// the message has no `sentAtMs` (matches React's `MessageTimestamp` early
/// return on a falsy epoch). Kept local + dep-free so this atomic does not
/// pull `intl` into the widget tree -- a later atomic can swap this for
/// `DateFormat.Hm()` once a locale-aware timestamp is wanted.
String? _formatClock(BigInt? sentAtMs) {
  if (sentAtMs == null) return null;
  final ms = sentAtMs.toInt();
  final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Stable per-device avatar color: a hash of the device name picks one of a
/// small fixed palette so the same sender always gets the same tint and
/// different senders usually get different tints (matching React's `Avatar`
/// behavior). Mirrors the `_avatarColor` helper in sessions_screen.dart;
/// duplicated here (not imported) so this atomic does not touch
/// sessions_screen.dart's surface, per the task scope.
Color _avatarColor(String deviceName) {
  const palette = [
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.brown,
    Colors.pink,
    Colors.cyan,
    Colors.amber,
  ];
  var hash = 0;
  for (final code in deviceName.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}
