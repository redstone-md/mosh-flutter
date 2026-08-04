// Extracted from `channel_screen.dart` (S5-1) as a public widget so the
// screen stays under the AGENTS.md 500-line ceiling. Pure move: the body
// interior (`ChannelScreenBody`) builds this in the `async.when` data
// branch. Behavior is byte-identical to the former private
// `_ChannelMessageListView` -- only the leading underscore dropped and
// the file-scoped attachment helpers moved here (renamed public).
//
// Message list view. `reverse: true` keeps the newest message at the bottom
// (mirrors DmScreen's `_MessageListView`); grouping via
// [groupChannelMessages] (the 5-min, same-`fromFingerprint` rule ported
// from React `messageItems`/`shouldGroup`) so only the first row of a
// group renders the sender meta. Rows are [ChannelMessageRow] instances
// from `channel_message_row.dart`.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart' show PeerActions;
import 'package:mosh/src/features/channel/channel_message_row.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView, AttachmentDescriptor;

class ChannelMessageListView extends StatelessWidget {
  const ChannelMessageListView({
    super.key,
    required this.messages,
    required this.ownFingerprint,
    required this.attachments,
    required this.attachmentCallbacks,
    required this.onRetryMessage,
    required this.peer,
  });

  final List<ChannelMessage> messages;
  final String ownFingerprint;
  final List<AttachmentView> attachments;

  /// Per-row transfer-action callbacks (download/cancel/open). Built by the
  /// screen from the Gateway seam + invalidate + open (mirrors DmScreen's
  /// `_attachmentCallbacks`).
  final ChannelAttachmentCallbacks Function(AttachmentView? view)
      attachmentCallbacks;

  /// Retry a failed outbound message by its messageId (React
  /// `retryChannelMessage`). Fire-and-forget via `unawaited` then
  /// invalidate the channel snapshot; the screen builds this from the
  /// Gateway seam.
  final void Function(String messageId) onRetryMessage;

   /// Peer-DM actions threaded into each [ChannelMessageRow]'s
   /// [MultiPartySenderMeta] (React `PeerActions`). Built by the screen
   /// from its offered set + offer-busy flag + the `_onPeerMessage`
   /// closure (createInvite + sendChannelDmOffer + navigate).
   final PeerActions peer;

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
             : findChannelAttachmentView(
                 attachments, msg.attachment!.attachmentId);
         final callbacks = attachmentCallbacks(attachmentView);
         return ChannelMessageRow(
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

/// Linear lookup for the channel attachment view by id (mirrors DmScreen's
/// `_findAttachmentView` -- a channel's attachment list is small, so a plain
/// scan avoids a Map).
AttachmentView? findChannelAttachmentView(
    List<AttachmentView> attachments, String attachmentId) {
  for (final v in attachments) {
    if (v.attachmentId == attachmentId) return v;
  }
  return null;
}

/// Per-row attachment transfer-action callbacks for the channel screen.
/// Mirrors DmScreen's `AttachmentCallbacks` value class (kept local to this
/// file to avoid coupling channel/group to the DM screen's class).
class ChannelAttachmentCallbacks {
  const ChannelAttachmentCallbacks({
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
