// Channel message row + grouping helper, extracted from `channel_screen.dart`
// to keep that screen under the 500-line ceiling. Ports React's
// `ChannelMessageRow` (src/features/private-dm/MessageLists.tsx) and the
// `messageItems` / `shouldGroup` rule 1-1, with the multi-party grouping key:
// `fromFingerprint` (NOT `fromDevice` like DMs -- channels are multi-party
// and display names are not unique; the fingerprint is the disambiguator).
//
// Grouping window: 5 minutes (React `GROUP_WINDOW_MS`). Only the FIRST row in
// a group renders the sender meta (`MultiPartySenderMeta`); grouped rows
// render a tighter vertical margin and omit the meta (matching React's
// `message-row-grouped` indent).
//
// The grouping helper is pure + @visibleForTesting so it can be unit-tested
// in isolation (mirrors `groupDmMessages` in `dm_screen.dart`). Server state
// lives in the parent `_ChannelMessageListView`; this row is a pure
// `StatelessWidget` driven by its ctor args (no providers, no async).
//
// NOTE: unlike `groupDmMessages` (which lives in the same file as its only
// caller, `DmScreen`, so `@visibleForTesting` is fine there), this helper
// lives in its own module and is called by `channel_screen.dart` in
// production, so it is a plain public API (not `@visibleForTesting`) -- the
// `invalid_use_of_visible_for_testing_member` lint would otherwise fire.

import 'package:flutter/material.dart';

import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/features/dm/attachment_card.dart';
import 'package:mosh/src/features/shared/failed_message_retry.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/l10n/app_localizations.dart';

/// Grouping window ported 1-1 from React `GROUP_WINDOW_MS`
/// (src/features/private-dm/MessageLists.tsx): 5 minutes. Shared with the
/// group helper (same React constant backs both).
const Duration channelGroupWindow = Duration(minutes: 5);

/// One grouping row: the message plus whether it was grouped under the
/// previous visible message (React `messageItems`/`shouldGroup`). The
/// channel analogue of `GroupedMessage` in `dm_screen.dart`, keyed by
/// `fromFingerprint` instead of `fromDevice`.
class GroupedChannelMessage {
  const GroupedChannelMessage({
    required this.message,
    required this.grouped,
  });

  final ChannelMessage message;
  final bool grouped;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupedChannelMessage &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          grouped == other.grouped;

  @override
  int get hashCode => Object.hash(message, grouped);
}

/// Computes the per-message `grouped` flag for the channel list (React
/// `messageItems` / `shouldGroup` in MessageLists.tsx, keyed by
/// `fromFingerprint`). Chronological, oldest -> newest: the first message
/// is never grouped; a row groups when its `fromFingerprint` equals the
/// previous one AND both `sentAtMs` are non-null AND `current >= previous`
/// AND the delta is within [channelGroupWindow] (5 min). A null `sentAtMs`
/// breaks grouping (React's `!prev || !cur` guard); the screen reverses the
/// result for display (reverse=true). Public (NOT `@visibleForTesting`)
/// because the screen's `_ChannelMessageListView` calls it in production;
/// unit tests exercise it via the same public seam.
List<GroupedChannelMessage> groupChannelMessages(
    List<ChannelMessage> messages) {
  final result = <GroupedChannelMessage>[];
  for (var i = 0; i < messages.length; i++) {
    final current = messages[i];
    final grouped = i > 0 && _channelShouldGroup(messages[i - 1], current);
    result.add(GroupedChannelMessage(message: current, grouped: grouped));
  }
  return result;
}

bool _channelShouldGroup(ChannelMessage previous, ChannelMessage current) {
  final prevMs = previous.sentAtMs;
  final curMs = current.sentAtMs;
  if (prevMs == null || curMs == null) return false;
  if (previous.fromFingerprint != current.fromFingerprint) return false;
  if (curMs < prevMs) return false;
  return curMs - prevMs <= BigInt.from(channelGroupWindow.inMilliseconds);
}

/// Channel-typed wrapper over the shared generic [filterMessages]
/// (lib/src/features/dm/conversation_tools.dart). Mirrors React's
/// `ChannelChatList` passing its `ChannelMessage[]` to the generic
/// `filterMessages<T>` (MessageLists.tsx). The search text is the GENERIC
/// one -- `fromDevice`, `body`, `attachment.fileName`, `attachment.mime` --
/// and does NOT include `fromFingerprint`, matching React (the channel
/// `*ChatList` calls the SAME generic `filterMessages` with no fingerprint
/// in the searchable text).
///
/// The screen applies this BEFORE [groupChannelMessages] (React's
/// filter-then-group order), so the grouping window is computed across the
/// visible set. Public (NOT `@visibleForTesting`) because the screen's
/// `_ChannelMessageListView` calls it in production; unit tests exercise it
/// via the same public seam.
List<ChannelMessage> filterChannelMessages(
  List<ChannelMessage> messages,
  String search,
  ConversationFilter filter,
) =>
    filterMessages(
      messages,
      search,
      filter,
      (m) => _ChannelSearchable(m),
    );

/// [SearchableMessage] view over a [ChannelMessage] (the generated type
/// shares no base with `ChatMessage` / `GroupMessage`, so a tiny adapter
/// exposes the searchable fields to the generic [filterMessages]).
class _ChannelSearchable implements SearchableMessage {
  const _ChannelSearchable(this._m);

  final ChannelMessage _m;

  @override
  String get fromDevice => _m.fromDevice;

  @override
  String get body => _m.body;

  @override
  AttachmentDescriptor? get attachment => _m.attachment;
}

/// One channel message row (React `ChannelMessageRow`). Own =
/// `fromFingerprint == ownFingerprint` (fingerprint comparison, NOT display
/// name -- channels are multi-party). The first row of a group renders the
/// `MultiPartySenderMeta` (fromDevice + shortened fingerprint + timestamp,
/// NO MLS badge -- React `ChannelMessageRow` omits the badge that
/// `GroupMessageRow` keeps); grouped rows render a tighter vertical margin
/// and omit the meta (matching React's `message-row-grouped` indent +
/// omitted meta). The meta renders on every non-grouped row, including
/// the user's own (React `PeerNickname` bolds the own name; mirrors the
/// DM port's `if (!grouped)` gate).
/// Own rows align right with a primaryContainer bubble; others align left
/// with a surfaceContainerHighest bubble. The [AttachmentCard] renders
/// under the body when `message.attachment != null` (display-only: the
/// transfer callbacks are no-op stubs until the channel attachment-transfer
/// seam arrives). No avatar or retry row yet (deferred to later atomics).
class ChannelMessageRow extends StatelessWidget {
  const ChannelMessageRow({
    super.key,
    required this.message,
    required this.ownFingerprint,
    required this.grouped,
    this.attachmentView,
    required this.onAttachmentDownload,
    required this.onAttachmentCancel,
    required this.onAttachmentOpen,
    required this.l,
  });

  final ChannelMessage message;
  final String ownFingerprint;
  final bool grouped;
  final AttachmentView? attachmentView;

  /// Transfer-action callbacks for the [AttachmentCard] (React
  /// `attachments.onDownload`/`onCancel`/`onOpen`). The channel attachment-
  /// transfer Gateway seam is a LATER atomic, so the screen wires these as
  /// no-op stubs for now (display-only stage, mirroring the DM port's
  /// `b7660f8`).
  final void Function(String attachmentId) onAttachmentDownload;
  final void Function(String attachmentId) onAttachmentCancel;
  final void Function(AttachmentDescriptor descriptor) onAttachmentOpen;

  /// Localized strings for the [FailedMessageRetry] row (the React
  /// component inlined "Failed to send" / "Retry" / "Retry failed message";
  /// the Flutter port localizes them via ARB).
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final own = message.fromFingerprint == ownFingerprint;
    final theme = Theme.of(context);
    final bubble = own
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final alignment = own ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: EdgeInsets.symmetric(vertical: grouped ? 1 : 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bubble,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: alignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!grouped)
                MultiPartySenderMeta(
                  fromDevice: message.fromDevice,
                  fromFingerprint: message.fromFingerprint,
                  sentAtMs: message.sentAtMs,
                  showMlsBadge: false,
                ),
              Text(message.body),
              if (message.attachment != null)
                AttachmentCard(
                  descriptor: message.attachment!,
                  view: attachmentView,
                  own: own,
                  onDownload: onAttachmentDownload,
                  onCancel: onAttachmentCancel,
                  onOpen: onAttachmentOpen,
                ),
              // FailedMessageRetry row (React `FailedMessageRetry`,
              // MessageLists.tsx L434-468) -- renders BELOW the body +
              // AttachmentCard, inside the message bubble's Column,
              // mirroring React's `<div className="message-body"> ...
              // <FailedMessageRetry/></div>` order. Gate is the 1-в-1 port
              // of React's render condition: `outbound && delivery_status
              // === "failed" && retryable && message_id` (outbound == own
              // == fromFingerprint == ownFingerprint). RENDER-ONLY: the
              // `onRetry` callback is a NO-OP STUB; the Gateway retry seam
              // (Rust `channel_retry_message` + frb codegen + Gateway
              // method) is a LATER atomic.
              if (own &&
                  message.deliveryStatus == MessageDeliveryStatus.failed &&
                  message.retryable == true &&
                  message.messageId != null)
                // TODO(channel-group-retry-seam): wire onRetry to the
                // Gateway retry method (React `retryChannelMessage`,
                // native-messaging-gateway.ts L494 + Rust
                // `channel_retry_message`, src-tauri/src/lib.rs L780) once
                // the Flutter Gateway ports it. No-op stub for the
                // display-only stage (mirrors the AttachmentCard atomic's
                // `b879a02` no-op stub pattern).
                FailedMessageRetry(
                  deliveryError: message.deliveryError,
                  onRetry: () {},
                  l: l.toFailedMessageRetryL10n(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
