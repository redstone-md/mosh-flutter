// Extracted from `group_screen.dart` (S5-x) as a public widget so the
// screen stays under the AGENTS.md 500-line ceiling. Pure move: the body
// interior (`GroupScreenBody`) builds this in the `async.when` data
// branch. Behavior is byte-identical to the former private
// `_GroupMessageListView` -- only the leading underscore dropped and
// the file-scoped attachment helpers moved here (renamed public).
//
// Message list view. `reverse: true` keeps the newest message at the bottom
// (mirrors ChannelScreen's `_ChannelMessageListView`); grouping via
// [groupGroupMessages] (the 5-min, same-`fromFingerprint` rule ported
// from React `messageItems`/`shouldGroup`) so only the first row of a
// group renders the sender meta. Rows are [GroupMessageRow] instances
// from `group_message_row.dart`.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/group/group_message_row.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor;

class GroupMessageListView extends StatelessWidget {
  const GroupMessageListView({
    super.key,
    required this.messages,
    required this.ownFingerprint,
    required this.attachments,
    required this.attachmentCallbacks,
    required this.onRetryMessage,
    required this.peer,
  });

  final List<GroupMessage> messages;
  final String ownFingerprint;
  final List<AttachmentView> attachments;

  /// Per-row transfer-action callbacks (download/cancel/open). Built by the
  /// screen from the Gateway seam + invalidate + open (mirrors DmScreen's
  /// `_attachmentCallbacks`).
  final GroupAttachmentCallbacks Function(AttachmentView? view)
      attachmentCallbacks;

  /// Retry a failed outbound message by its messageId (React
  /// `retryGroupMessage`). Fire-and-forget via `unawaited` then
  /// invalidate the group snapshot; the screen builds this from the
  /// Gateway seam.
  final void Function(String messageId) onRetryMessage;

   /// Peer-DM actions threaded into each [GroupMessageRow]'s
   /// [MultiPartySenderMeta] (React `PeerActions`). Built by the screen
   /// from its offered set + offer-busy flag + the `_onPeerMessage`
   /// closure (createInvite + sendGroupDmOffer + navigate).
   final PeerActions peer;

   @override
   Widget build(BuildContext context) {
     // Chronological grouping (oldest -> newest), then reversed for the
     // reverse=true ListView (newest at the bottom). Mirrors ChannelScreen.
     final grouped = groupGroupMessages(messages).reversed.toList();
     final l = AppLocalizations.of(context)!;
     return ListView.builder(
       // React `.chat-scroll { padding: 16px 22px }`.
       padding: kChatScrollPadding,
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
             : findGroupAttachmentView(
                 attachments, msg.attachment!.attachmentId);
         final callbacks = attachmentCallbacks(attachmentView);
         return GroupMessageRow(
           message: msg,
           ownFingerprint: ownFingerprint,
           grouped: item.grouped,
           attachmentView: attachmentView,
           peer: peer,
           l: l,
           onAttachmentDownload: callbacks.onDownload,
           onAttachmentCancel: callbacks.onCancel,
           onAttachmentOpen: callbacks.onOpen,
           busy: callbacks.busy,
           onRetry: onRetryMessage,
         );
       },
     );
   }
}

/// Linear lookup for the group attachment view by id (mirrors DmScreen's
/// `_findAttachmentView` -- a group's attachment list is small, so a plain
/// scan avoids a Map).
AttachmentView? findGroupAttachmentView(
    List<AttachmentView> attachments, String attachmentId) {
  for (final v in attachments) {
    if (v.attachmentId == attachmentId) return v;
  }
  return null;
}

/// Per-row attachment transfer-action callbacks for the group screen.
/// Mirrors DmScreen's `AttachmentCallbacks` value class (kept local to this
/// file to avoid coupling channel/group to the DM screen's class).
class GroupAttachmentCallbacks {
  const GroupAttachmentCallbacks({
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final bool busy;
  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;
}
