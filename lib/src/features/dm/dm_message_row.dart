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
import 'package:mosh/src/features/shared/avatar.dart';
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
    required this.busy,
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
  final bool busy;
  final void Function(String messageId) onRetry;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final avatarSlot = grouped
        // React renders `.avatar.avatar-spacer` -- the same box, hidden --
        // so a grouped row stays indented under the first row's avatar.
        ? const SizedBox(width: dmMessageAvatarSize)
        : Avatar(
            name: message.fromDevice,
            radius: dmMessageAvatarSize / 2,
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
                children: [
                  if (!grouped) SenderMeta(message: message),
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
        ],
      ),
    );
  }
}
