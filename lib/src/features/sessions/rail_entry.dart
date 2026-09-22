// One row of the sessions rail: which conversation it opens, and the chrome
// that conversation's kind wants.
//
// The rail used to hold one near-identical block per kind, and each block
// wrote the `kind:id` key by hand three times -- once for the unread lookup,
// once for the active highlight and once for the clear-on-tap. A typo in a
// prefix was a silent bug, not a compile error. Here the key is written
// once, in [RailEntry.ref], and the rail loops over entries instead of over
// kinds: it asks an entry which conversation it opens, then hands the row
// back the three things it computed from that answer. A new kind adds one
// subclass; the rail's loop does not change.
//
// Every row renders through [RailItem], the shared rail-row widget -- the
// pending-DM-offer row included, which used to hand-roll its own `ListTile`
// shape.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show UnreadBadge;
import 'package:mosh/src/features/conversation/peer_label.dart' show peerLabel;
import 'package:mosh/src/features/conversation/dm_state.dart' show dmStateLabel;
import 'package:mosh/src/features/sessions/rail_item.dart'
    show RailItem, RailItemKind;
import 'package:mosh/src/features/shared/avatar.dart' show Avatar;
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind, ConversationRef;
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;
import 'package:mosh/src/state/dm_offer_providers.dart' show PendingDmOffer;
import 'package:mosh/src/util/format.dart' show shorten;

/// What the rail knows about a row and the row does not: its unread count,
/// whether it is the open conversation, and the hook that clears the badge
/// and marks the conversation open.
///
/// All three come from the row's [RailEntry.ref], so a row that opens no
/// conversation gets zero, false and null -- there is no badge to clear and
/// no conversation to mark open.
typedef RailRowChrome = ({
  int unreadCount,
  bool active,
  VoidCallback? onSelect,
});

/// One row of the sessions rail: the conversation it opens, plus the chrome
/// that conversation's kind wants.
sealed class RailEntry {
  const RailEntry();

  /// The conversation this row opens, or null for a row that opens no
  /// conversation yet -- a pending DM offer has no session behind it until
  /// it is accepted.
  ConversationRef? get ref;

  /// This row's widget. [chrome] is what the rail computed from [ref]; the
  /// row decides what to render with it.
  Widget buildRow(BuildContext context, RailRowChrome chrome);
}

/// One DM session row: an avatar with the label's initials via
/// [avatarInitials] (background colour a stable hash of the label, so two
/// sessions with the same peer match), the label as title (falling back
/// peer -> own display -> raw session id, the same chain `dm_screen` uses),
/// the localized state label as subtitle -- or, when this DM's linked peer
/// is no longer in the org roster, the revoked badge -- an `UnreadBadge`
/// when count > 0, and an onTap that navigates to the DM screen.
final class DmRailEntry extends RailEntry {
  const DmRailEntry(this.session, {this.revokedOrgName});

  final SessionSnapshot session;

  /// The org the peer left, when this DM is org-bound and the peer is no
  /// longer in the roster. The rail looks it up in
  /// `revokedDmBadgesProvider`; null keeps the state subtitle.
  final String? revokedOrgName;

  @override
  ConversationRef get ref =>
      ConversationRef(kind: ConversationKind.dm, id: session.sessionId);

  @override
  Widget buildRow(BuildContext context, RailRowChrome chrome) {
    final l = AppLocalizations.of(context)!;
    final label = peerLabel(l, session);
    return Semantics(
      label: l.openSessionAria(label),
      button: true,
      selected: chrome.active,
      child: RailItem(
        kind: RailItemKind.dm,
        leading: Avatar(name: label),
        title: label,
        subtitle: revokedOrgName != null
            ? '${l.orgRevokedBadge} $revokedOrgName'
            : dmStateLabel(l, session.state),
        // The expanded rail hides `.rail-dot`, so the badge stands alone.
        trailing: UnreadBadge(count: chrome.unreadCount),
        active: chrome.active,
        onTap: () {
          // Clear the badge + mark the conversation open first, then
          // navigate.
          chrome.onSelect?.call();
          context.go(AppRoutes.dmFor(session.sessionId));
        },
      ),
    );
  }
}

/// One channel row: leading `Icons.tag`, title `#<name>`, subtitle the
/// topic, trailing `UnreadBadge`. `onTap` opens the channel screen.
final class ChannelRailEntry extends RailEntry {
  const ChannelRailEntry(this.channel);

  final ChannelSnapshot channel;

  @override
  ConversationRef get ref =>
      ConversationRef(kind: ConversationKind.channel, id: channel.name);

  @override
  Widget buildRow(BuildContext context, RailRowChrome chrome) {
    final l = AppLocalizations.of(context)!;
    return Semantics(
      label: l.openChannelAria(channel.name),
      button: true,
      selected: chrome.active,
      child: RailItem(
        kind: RailItemKind.channel,
        leading: const Icon(Icons.tag),
        title: '#${channel.name}',
        // An empty topic yields no subtitle line ([RailItem] hides it).
        subtitle: channel.topic,
        trailing: UnreadBadge(count: chrome.unreadCount),
        active: chrome.active,
        onTap: () {
          chrome.onSelect?.call();
          context.go(AppRoutes.channelFor(channel.name));
        },
      ),
    );
  }
}

/// One group row: leading `Icons.group`, title the group label (falling
/// back to a shortened group id), subtitle the member count, trailing
/// `UnreadBadge`. `onTap` opens the group screen.
final class GroupRailEntry extends RailEntry {
  const GroupRailEntry(this.group);

  final GroupSnapshot group;

  @override
  ConversationRef get ref =>
      ConversationRef(kind: ConversationKind.group, id: group.groupId);

  @override
  Widget buildRow(BuildContext context, RailRowChrome chrome) {
    final l = AppLocalizations.of(context)!;
    final label = group.label ?? shorten(group.groupId, 6);
    return Semantics(
      label: l.openGroupAria(label),
      button: true,
      selected: chrome.active,
      child: RailItem(
        kind: RailItemKind.group,
        leading: const Icon(Icons.group),
        title: label,
        // `memberCount` is a `BigInt`; narrowing to `int` is safe for
        // realistic member counts.
        subtitle: l.membersCount(group.memberCount.toInt()),
        // The expanded rail hides `.rail-admin-crown` and `.rail-dot`
        // outright, so the badge is the only trailing element.
        trailing: UnreadBadge(count: chrome.unreadCount),
        active: chrome.active,
        onTap: () {
          chrome.onSelect?.call();
          context.go(AppRoutes.groupFor(group.groupId));
        },
      ),
    );
  }
}

/// One pending DM-offer row: the whole row accepts, the trailing X
/// dismisses.
///
/// It is the one row that opens no conversation: [ref] is null, because an
/// offer has no session behind it until it is accepted. It takes the accept
/// and dismiss callbacks straight from the rail's actions instead.
final class OfferRailEntry extends RailEntry {
  const OfferRailEntry({
    required this.pending,
    required this.onAccept,
    required this.onDismiss,
  });

  final PendingDmOffer pending;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  ConversationRef? get ref => null;

  @override
  Widget buildRow(BuildContext context, RailRowChrome chrome) {
    final l = AppLocalizations.of(context)!;
    final fromDevice = pending.offer.fromDevice;
    return Semantics(
      label: l.railOfferAccept(fromDevice),
      button: true,
      child: RailItem(
        kind: RailItemKind.dm,
        leading: Avatar(name: fromDevice),
        title: fromDevice,
        subtitle: pending.kind == ConversationKind.channel
            ? '#${pending.host}'
            : l.onboardGroupInvite,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Offer badge icon.
            Icon(Icons.chat_bubble_outline,
                size: 14, color: Theme.of(context).colorScheme.primary),
            // A button inside the row's own
            // tap target: the inner button wins the gesture arena, so the
            // X dismisses and never accepts.
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: l.railOfferDismiss,
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
            ),
          ],
        ),
        onTap: onAccept,
      ),
    );
  }
}
