// Group message row + grouping helper, extracted from `group_screen.dart`
// to keep that screen under the 500-line ceiling. Ports React's
// `GroupMessageRow` (src/features/private-dm/MessageLists.tsx) and the
// `messageItems` / `shouldGroup` rule 1-1, with the multi-party grouping key:
// `fromFingerprint` (NOT `fromDevice` like DMs -- groups are multi-party
// and display names are not unique; the fingerprint is the disambiguator).
//
// Grouping window: 5 minutes (React `GROUP_WINDOW_MS`). Only the FIRST row in
// a group renders the sender meta (`MultiPartySenderMeta`); grouped rows
// render a tighter vertical margin and omit the meta (matching React's
// `message-row-grouped` indent).
//
// The grouping helper is pure + @visibleForTesting so it can be unit-tested
// in isolation (mirrors `groupDmMessages` in `dm_screen.dart`). Server state
// lives in the parent `_GroupMessageListView`; this row is a pure
// `StatelessWidget` driven by its ctor args (no providers, no async).
//
// The grouping shape is byte-identical to `groupChannelMessages` (both
// React `ChannelChatList` / `GroupChatList` use `messageItems(...,
// from_fingerprint)`); the two helpers are kept separate rather than shared
// because their message types (`ChannelMessage` vs `GroupMessage`) are
// distinct generated classes with no shared base -- a single generic helper
// would force an unidiomatic adapter or a `dynamic` cast, hurting the
// type safety the rest of the port preserves. Each helper is a small,
// pure, easily-tested function, so the duplication is shallow and local.
//
// NOTE: unlike `groupDmMessages` (which lives in the same file as its only
// caller, `DmScreen`, so `@visibleForTesting` is fine there), this helper
// lives in its own module and is called by `group_screen.dart` in
// production, so it is a plain public API (not `@visibleForTesting`) -- the
// `invalid_use_of_visible_for_testing_member` lint would otherwise fire.

import 'package:flutter/material.dart';

import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/failed_message_retry.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/l10n/app_localizations.dart';

/// Grouping window ported 1-1 from React `GROUP_WINDOW_MS`
/// (src/features/private-dm/MessageLists.tsx): 5 minutes. Mirrors
/// `channelGroupWindow` in `channel_message_row.dart` (same React constant).
const Duration groupGroupWindow = Duration(minutes: 5);

/// One grouping row: the message plus whether it was grouped under the
/// previous visible message (React `messageItems`/`shouldGroup`). The
/// group analogue of `GroupedMessage` in `dm_screen.dart`, keyed by
/// `fromFingerprint` instead of `fromDevice`.
class GroupedGroupMessage {
  const GroupedGroupMessage({
    required this.message,
    required this.grouped,
  });

  final GroupMessage message;
  final bool grouped;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupedGroupMessage &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          grouped == other.grouped;

  @override
  int get hashCode => Object.hash(message, grouped);
}

/// Computes the per-message `grouped` flag for the group list (React
/// `messageItems` / `shouldGroup` in MessageLists.tsx, keyed by
/// `fromFingerprint`). Chronological, oldest -> newest: the first message
/// is never grouped; a row groups when its `fromFingerprint` equals the
/// previous one AND both `sentAtMs` are non-null AND `current >= previous`
/// AND the delta is within [groupGroupWindow] (5 min). A null `sentAtMs`
/// breaks grouping (React's `!prev || !cur` guard); the screen reverses the
/// result for display (reverse=true). Public (NOT `@visibleForTesting`)
/// because the screen's `_GroupMessageListView` calls it in production;
/// unit tests exercise it via the same public seam.
List<GroupedGroupMessage> groupGroupMessages(List<GroupMessage> messages) {
  final result = <GroupedGroupMessage>[];
  for (var i = 0; i < messages.length; i++) {
    final current = messages[i];
    final grouped = i > 0 && _groupShouldGroup(messages[i - 1], current);
    result.add(GroupedGroupMessage(message: current, grouped: grouped));
  }
  return result;
}

bool _groupShouldGroup(GroupMessage previous, GroupMessage current) {
  final prevMs = previous.sentAtMs;
  final curMs = current.sentAtMs;
  if (prevMs == null || curMs == null) return false;
  if (previous.fromFingerprint != current.fromFingerprint) return false;
  if (curMs < prevMs) return false;
  return curMs - prevMs <= BigInt.from(groupGroupWindow.inMilliseconds);
}

/// Group-typed wrapper over the shared generic [filterMessages]
/// (lib/src/features/conversation/conversation_tools.dart). Mirrors React's
/// `GroupChatList` passing its `GroupMessage[]` to the generic
/// `filterMessages<T>` (MessageLists.tsx). The search text is the GENERIC
/// one -- `fromDevice`, `body`, `attachment.fileName`, `attachment.mime` --
/// and does NOT include `fromFingerprint`, matching React (the group
/// `*ChatList` calls the SAME generic `filterMessages` with no fingerprint
/// in the searchable text).
///
/// The screen applies this BEFORE [groupGroupMessages] (React's
/// filter-then-group order), so the grouping window is computed across the
/// visible set. Public (NOT `@visibleForTesting`) because the screen's
/// `_GroupMessageListView` calls it in production; unit tests exercise it
/// via the same public seam.
List<GroupMessage> filterGroupMessages(
  List<GroupMessage> messages,
  String search,
  ConversationFilter filter,
) =>
    filterMessages(
      messages,
      search,
      filter,
      (m) => _GroupSearchable(m),
    );

/// [SearchableMessage] view over a [GroupMessage] (the generated type
/// shares no base with `ChatMessage` / `ChannelMessage`, so a tiny adapter
/// exposes the searchable fields to the generic [filterMessages]).
class _GroupSearchable implements SearchableMessage {
  const _GroupSearchable(this._m);

  final GroupMessage _m;

  @override
  String get fromDevice => _m.fromDevice;

  @override
  String get body => _m.body;

  @override
  AttachmentDescriptor? get attachment => _m.attachment;
}

/// One group message row (React `GroupMessageRow`). Own =
/// `fromFingerprint == ownFingerprint` (fingerprint comparison, NOT display
/// name -- groups are multi-party). The first row of a group renders the
/// `MultiPartySenderMeta` (fromDevice + shortened fingerprint + MLS badge +
/// timestamp); grouped rows render a tighter vertical margin and omit the
/// meta (matching React's `message-row-grouped` indent + omitted meta).
/// The meta renders on every non-grouped row, including the user's own
/// (React `PeerNickname` bolds the own name; mirrors the DM port's
/// `if (!grouped)` gate).
/// The [AttachmentCard] renders
/// under the body when `message.attachment != null` (display-only: the
/// transfer callbacks are no-op stubs until the group attachment-transfer
/// seam arrives). The avatar slot mirrors `DmMessageRow` (React `.avatar` +
/// `avatar avatar-spacer`): real `CircleAvatar` on the first row of a group,
/// a same-width `SizedBox` spacer on grouped rows. Every row is
/// left-aligned -- React has no bubbles and no own-vs-peer side.
class GroupMessageRow extends StatelessWidget {
  const GroupMessageRow({
    super.key,
    required this.message,
    required this.ownFingerprint,
    required this.grouped,
    this.attachmentView,
    this.peer,
    required this.onAttachmentDownload,
    required this.onAttachmentCancel,
    required this.onAttachmentOpen,
    required this.busy,
    required this.onRetry,
    required this.l,
  });

  final GroupMessage message;
  final String ownFingerprint;
  final bool grouped;
  final AttachmentView? attachmentView;

  /// Optional per-conversation peer actions (React `PeerActions`). `null`
  /// (the default) keeps the sender name a plain bold `Text` -- the
  /// DM-row + existing-tests case. The screen sets this on non-grouped
  /// rows so a non-own name opens the PeerNickname popover. See
  /// [MultiPartySenderMeta.peer].
  final PeerActions? peer;

  /// Transfer-action callbacks for the [AttachmentCard] (React
  /// `attachments.onDownload`/`onCancel`/`onOpen`). The group attachment-
  /// transfer Gateway seam is a LATER atomic, so the screen wires these as
  /// no-op stubs for now (display-only stage, mirroring the DM port's
  /// `b7660f8`).
  final void Function(String attachmentId) onAttachmentDownload;
  final void Function(String attachmentId) onAttachmentCancel;
  final void Function(AttachmentDescriptor descriptor) onAttachmentOpen;
  final bool busy;

  /// Retry callback for the [FailedMessageRetry] row (React
  /// `onRetryMessage`). The screen wires this to the Gateway retry seam
  /// (`retryGroupMessage` -> frb `private_group_retry_message`); fire-and-
  /// forget via `unawaited` then invalidate the group snapshot (mirrors
  /// the attachment download/cancel wiring).
  final void Function(String messageId) onRetry;

  /// Localized strings for the [FailedMessageRetry] row (the React
  /// component inlined "Failed to send" / "Retry" / "Retry failed message";
  /// the Flutter port localizes them via ARB).
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final own = message.fromFingerprint == ownFingerprint;
    // React renders every row identically -- avatar (or a hidden spacer on a
    // grouped continuation) then the body, always left-aligned. There is no
    // bubble and no own-vs-peer side; `own` only gates the retry affordance.
    final avatarSlot = grouped
        ? const SizedBox(width: messageAvatarSize)
        : Avatar(
            name: message.fromDevice,
            radius: messageAvatarSize / 2,
          );
    return Padding(
      padding: EdgeInsets.only(top: messageRowSpacing(grouped)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatarSlot,
          const SizedBox(width: kMessageRowGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!grouped)
                  MultiPartySenderMeta(
                    fromDevice: message.fromDevice,
                    fromFingerprint: message.fromFingerprint,
                    sentAtMs: message.sentAtMs,
                    peer: peer,
                  ),
                if (message.body.isNotEmpty)
                  Text(message.body, style: kMessageBodyStyle),
                if (message.attachment != null)
                  AttachmentCard(
                    descriptor: message.attachment!,
                    view: attachmentView,
                    own: own,
                    busy: busy,
                    onDownload: onAttachmentDownload,
                    onCancel: onAttachmentCancel,
                    onOpen: onAttachmentOpen,
                  ),
                // FailedMessageRetry row (React FailedMessageRetry,
                // MessageLists.tsx L434-468) -- renders BELOW the body +
                // AttachmentCard, inside the message bubble's Column,
                // mirroring React's message-body order (FailedMessageRetry
                // last child). Gate is the 1-1 port of React's render
                // condition: outbound && delivery_status === 'failed' &&
                // retryable && message_id (outbound == own ==
                // fromFingerprint == ownFingerprint). The onRetry
                // callback fires the Gateway retry seam
                // (retryGroupMessage -> frb private_group_retry_message);
                // the gate guarantees message.messageId is non-null,
                // so the bang (!) is safe.
                if (own &&
                    message.deliveryStatus == MessageDeliveryStatus.failed &&
                    message.retryable == true &&
                    message.messageId != null)
                  FailedMessageRetry(
                    deliveryError: message.deliveryError,
                    onRetry: () => onRetry(message.messageId!),
                    l: l.toFailedMessageRetryL10n(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
