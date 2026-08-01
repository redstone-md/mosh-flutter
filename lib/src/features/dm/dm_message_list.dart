// DM message list view extracted from `dm_screen.dart` to keep that screen
// under the 500-line ceiling. Owns the per-session `ListView.builder` that
// maps `ChatMessage`s into `DmMessageRow`s, plus the grouping rule (React
// `messageItems`/`shouldGroup` 1-1 port) and the attachment-view lookup.
//
// Mirrors `channel_message_row.dart`/`group_message_row.dart` being separate
// from their screens. The grouping helper + `DmGroupedMessage` are public so
// `dm_screen_grouping_test` can exercise them via a normal import (the old
// `@visibleForTesting` seam lived in `dm_screen.dart`; moving them out lets
// the test drop the `@visibleForTesting` indirection).

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_message_row.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Grouping window ported 1-1 from React `GROUP_WINDOW_MS`
/// (src/features/private-dm/MessageLists.tsx): 5 minutes.
const Duration dmGroupWindow = Duration(minutes: 5);

/// One grouping row: the message plus whether it was grouped under the
/// previous visible message (React `messageItems`/`shouldGroup`).
class DmGroupedMessage {
  const DmGroupedMessage({required this.message, required this.grouped});

  final ChatMessage message;
  final bool grouped;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DmGroupedMessage &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          grouped == other.grouped;

  @override
  int get hashCode => Object.hash(message, grouped);
}

/// Computes the per-message `grouped` flag (React `messageItems` /
/// `shouldGroup` in MessageLists.tsx). Chronological, oldest -> newest: the
/// first message is never grouped; a row groups when its `fromDevice`
/// equals the previous one AND both `sentAtMs` are non-null AND `current >=
/// previous` AND the delta is within [dmGroupWindow] (5 min). A null
/// `sentAtMs` breaks grouping (React's `!prev || !cur` guard); the screen
/// reverses the result for display (reverse=true).
List<DmGroupedMessage> groupDmMessages(List<ChatMessage> messages) {
  final result = <DmGroupedMessage>[];
  for (var i = 0; i < messages.length; i++) {
    final current = messages[i];
    final grouped = i > 0 && _shouldGroup(messages[i - 1], current);
    result.add(DmGroupedMessage(message: current, grouped: grouped));
  }
  return result;
}

bool _shouldGroup(ChatMessage previous, ChatMessage current) {
  final prevMs = previous.sentAtMs;
  final curMs = current.sentAtMs;
  if (prevMs == null || curMs == null) return false;
  if (previous.fromDevice != current.fromDevice) return false;
  if (curMs < prevMs) return false;
  return curMs - prevMs <= BigInt.from(dmGroupWindow.inMilliseconds);
}

/// Bundles the three transfer-action callbacks one card needs (React
/// `attachments.onDownload`/`onCancel`/`onOpen`); a class keeps the list
/// view's field type short. Built per-row so Open resolves THIS row's
/// `view.localPath`.
class DmAttachmentCallbacks {
  const DmAttachmentCallbacks({
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;
}

/// Linear lookup for the attachment view by id (session lists are small --
/// one DM's files -- so a plain scan avoids a Map).
AttachmentView? findDmAttachmentView(
    List<AttachmentView> attachments, String attachmentId) {
  for (final v in attachments) {
    if (v.attachmentId == attachmentId) return v;
  }
  return null;
}

/// The per-session message list view. Maps `ChatMessage`s (already grouped
/// chronologically + reversed by the screen) into `DmMessageRow`s. Own vs
/// peer is inferred from `ChatMessage.fromDevice` vs `ownDeviceName` (React's
/// `from_device === ownDeviceName` rule). Pure `StatelessWidget` driven by
/// ctor args (no providers, no async); the screen owns the server state.
class DmMessageListView extends StatelessWidget {
  const DmMessageListView({
    super.key,
    required this.grouped,
    required this.ownDeviceName,
    required this.attachments,
    required this.attachmentCallbacks,
    required this.onRetryMessage,
  });

  final List<DmGroupedMessage> grouped;
  final String ownDeviceName;
  final List<AttachmentView> attachments;
  final DmAttachmentCallbacks Function(AttachmentView? view)
      attachmentCallbacks;

  /// Retry a failed outbound DM message by its messageId (React
  /// `retryDmMessage`). Fire-and-forget via `unawaited` then invalidate the
  /// session snapshot; the screen builds this from the Gateway seam.
  final void Function(String messageId) onRetryMessage;

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
        final attachmentView = msg.attachment == null
            ? null
            : findDmAttachmentView(attachments, msg.attachment!.attachmentId);
        final callbacks = attachmentCallbacks(attachmentView);
        return DmMessageRow(
          message: msg,
          own: own,
          grouped: item.grouped,
          attachmentView: attachmentView,
          onAttachmentDownload: callbacks.onDownload,
          onAttachmentCancel: callbacks.onCancel,
          onAttachmentOpen: callbacks.onOpen,
         onRetry: onRetryMessage,
         l: AppLocalizations.of(context)!,
       );
      },
    );
  }
}
