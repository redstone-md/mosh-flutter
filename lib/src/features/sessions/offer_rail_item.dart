// OfferRailItem -- the 1-в-1 port of React's OfferRailItem (SessionRail.tsx),
// the row that surfaces a pending DM offer from a channel/group member at the
// top of the sessions rail. The whole row is an "accept" affordance (React
// `rail-item rail-offer-accept`); a trailing X is the "dismiss" affordance
// (React `rail-offer-dismiss`).
//
// React structure (SessionRail.tsx L157-198):
//   <div className="rail-offer">
//     <button className="rail-item rail-offer-accept" onClick={onAccept}
//       title/aria-label="Accept chat invite from {from_device}">
//       <Avatar name={from_device} />
//       <span className="rail-text">
//         <strong>{from_device}</strong>
//         <small>{kind === "channel" ? `#${host}` : "group invite"}</small>
//       </span>
//       <span className="rail-offer-badge"><IconMessageCircle size=10 /></span>
//     </button>
//     <button className="rail-offer-dismiss" onClick={onDismiss}
//       title/aria-label="Dismiss invite">
//       <IconX size=10 />
//     </button>
//   </div>
//
// Avatar uses [avatarColor] + [avatarInitials] from dm_helpers.dart (the same
// helpers _SessionRow uses) so an offer from a peer renders with the same
// avatar color/initials the eventual DM session will -- React's `<Avatar
// name={from_device} />` hashes the device name the same way.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/state/dm_offer_providers.dart';

/// One pending DM-offer row in the sessions rail. Mirrors React's
/// `OfferRailItem`: the whole row accepts (tapping it accepts the offer);
/// a trailing X dismisses. The avatar uses the offer's `fromDevice` (React
/// `<Avatar name={from_device} />`); the subtitle is `#host` for a channel
/// offer or "group invite" for a group offer.
class OfferRailItem extends StatelessWidget {
  const OfferRailItem({
    super.key,
    required this.pending,
    required this.onAccept,
    required this.onDismiss,
  });

  final PendingDmOffer pending;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fromDevice = pending.offer.fromDevice;
    // React `kind === "channel" ? `#${host}` : "group invite"`.
    final subtitle = pending.kind == PendingDmOfferKind.channel
        ? '#${pending.host}'
        : l.onboardGroupInvite;
    return Semantics(
      label: l.railOfferAccept(fromDevice),
      button: true,
      child: Row(
        children: [
          Expanded(
            // The whole row is the accept affordance (React's
            // rail-offer-accept button). A ListTile keeps the avatar + text
            // layout consistent with _SessionRow/ChannelRailItem/GroupRailItem.
            child: ListTile(
              dense: true,
              leading: Avatar(name: fromDevice),
              title: Text(
                fromDevice,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(subtitle,
                  style: theme.textTheme.bodySmall),
              trailing: Icon(Icons.chat_bubble_outline, size: 14,
                  color: theme.colorScheme.primary),
              onTap: onAccept,
            ),
          ),
          // The trailing dismiss X (React's rail-offer-dismiss). A compact
          // IconButton keeps a ~32px tap target without crowding the row.
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: l.railOfferDismiss,
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
