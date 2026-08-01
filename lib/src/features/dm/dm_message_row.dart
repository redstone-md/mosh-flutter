// DM message row extracted from `dm_screen.dart` to keep that screen under
// the 500-line ceiling. Ports the React `DmMessageRow` (src/features/
// private-dm/MessageLists.tsx) 1-1: alignment/color by `own`, an avatar
// slot (or a same-width spacer when grouped under the previous row),
// sender-meta + body + optional AttachmentCard + own DeliveryTicks. This
// widget owns the avatar diameter const so the spacer stays visually
// indented under a real avatar.
//
// Server state lives in the parent `_MessageListView`; this row is a pure
// `StatelessWidget` driven by its ctor args (no providers, no async).

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/attachment_card.dart';
import 'package:mosh/src/features/dm/call_log_entry.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/features/shared/failed_message_retry.dart';

/// Avatar diameter used by `DmMessageRow` -- both the real `CircleAvatar`
/// and the grouped-row spacer share this width so a grouped row stays
/// visually indented under the first row's avatar (matching React's
/// `avatar avatar-spacer` element).
const double dmMessageAvatarSize = 32;

/// One row in the DM message list. See file header for the grouping rule.
class DmMessageRow extends StatelessWidget {
  const DmMessageRow({
    super.key,
    required this.message,
    required this.own,
    required this.grouped,
    this.attachmentView,
    required this.onAttachmentDownload,
    required this.onAttachmentCancel,
    required this.onAttachmentOpen,
    required this.onRetry,
    required this.l,
  });

  final ChatMessage message;
  final bool own;
  final bool grouped;
  final AttachmentView? attachmentView;
  final void Function(String attachmentId) onAttachmentDownload;
  final void Function(String attachmentId) onAttachmentCancel;
  final void Function(AttachmentDescriptor descriptor) onAttachmentOpen;
  final void Function(String messageId) onRetry;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = own ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final align = own ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final mainAxisAlignment =
        own ? MainAxisAlignment.end : MainAxisAlignment.start;
    final avatarSlot = grouped
        ? const SizedBox(width: dmMessageAvatarSize)
        : CircleAvatar(
            backgroundColor: avatarColor(message.fromDevice),
            maxRadius: dmMessageAvatarSize / 2,
            child: Text(
              avatarInitials(message.fromDevice),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: align,
        children: [
          if (!own) avatarSlot,
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: align,
                children: [
                  if (!grouped) SenderMeta(message: message),
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
                 // React MessageLists.tsx L342:
                 //   {message.call_event ? <CallLogEntry event={...} /> : null}
                 // Renders BELOW the AttachmentCard + ABOVE DeliveryTicks,
                 // mirroring React's child order.
                 if (message.callEvent != null)
                   CallLogEntry(event: message.callEvent!, l: l),
                 if (own) DeliveryTicks(status: message.deliveryStatus),
                 // FailedMessageRetry row (React FailedMessageRetry,
                 // MessageLists.tsx L354-357) -- renders BELOW the body + AttachmentCard +
                 // DeliveryTicks, mirroring React's message-body order (FailedMessageRetry
                 // last child). Gate is the 1-1 port of React's render condition:
                 // outbound && delivery_status === 'failed' && retryable && message_id
                 // (outbound == own == from_device == ownDeviceName). The onRetry
                 // callback fires the Gateway retry seam (retryDmMessage -> frb
                 // private_dm_retry_message); the gate guarantees message.messageId is
                 // non-null, so the bang (!) is safe.
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
          ),
          if (own) avatarSlot,
        ],
      ),
    );
  }
}
