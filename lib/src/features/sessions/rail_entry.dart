import 'package:flutter/material.dart';
import 'package:mosh/src/state/chat_names_provider.dart' show chatDisplayName;
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show UnreadBadge;
import 'package:mosh/src/features/conversation/peer_label.dart' show peerLabel;
import 'package:mosh/src/features/conversation/dm_state.dart' show dmStateLabel;
import 'package:mosh/src/features/sessions/rail_item.dart'
    show RailItem, RailItemKind;
import 'package:mosh/src/features/sessions/rail_activity.dart';
import 'package:mosh/src/features/shared/avatar.dart' show Avatar;
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind, ConversationRef;
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot, DmSessionState;
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

  String originalName(AppLocalizations l) => switch (this) {
        DmRailEntry(:final session) => peerLabel(l, session),
        ChannelRailEntry(:final channel) => '#${channel.name}',
        GroupRailEntry(:final group) =>
          group.label ?? shorten(group.groupId, 6),
        OfferRailEntry() => '',
      };

  String? get personalName => null;
  String displayName(AppLocalizations l) =>
      chatDisplayName(originalName(l), personalName);

  RailActivity get activity => const RailActivity();

  String searchText(AppLocalizations l) => ref?.id ?? '';

  String? preview(AppLocalizations l) {
    final text = activity.text;
    if (text == null) return null;
    final prefix = activity.own
        ? l.chatListYou
        : ref?.kind == ConversationKind.dm
            ? null
            : activity.sender;
    return prefix == null ? text : '$prefix: $text';
  }

  String? timestamp(BuildContext context) {
    final at = activity.sentAtMs;
    if (at == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(at.toInt()).toLocal();
    final now = DateTime.now();
    final sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return sameDay
        ? MaterialLocalizations.of(
            context,
          ).formatTimeOfDay(TimeOfDay.fromDateTime(date))
        : MaterialLocalizations.of(context).formatShortDate(date);
  }

  /// This row's widget. [chrome] is what the rail computed from [ref]; the
  /// row decides what to render with it.
  Widget buildRow(BuildContext context, RailRowChrome chrome);
}

List<RailEntry> recentRailEntries(
  List<RailEntry> entries,
  AppLocalizations l, {
  String query = '',
  ConversationKind? kind,
}) {
  final search = query.trim().toLowerCase();
  final visible = entries
      .where(
        (entry) =>
            (kind == null || entry.ref?.kind == kind) &&
            entry.searchText(l).toLowerCase().contains(search),
      )
      .toList();
  visible.sort((a, b) {
    final aTime = a.activity.sentAtMs;
    final bTime = b.activity.sentAtMs;
    if (aTime != null && bTime != null) {
      final result = bTime.compareTo(aTime);
      if (result != 0) return result;
    } else if (aTime != null) {
      return -1;
    } else if (bTime != null) {
      return 1;
    }
    if (a.activity.text != null && b.activity.text == null) return -1;
    if (b.activity.text != null && a.activity.text == null) return 1;
    return (a.ref?.key ?? '').compareTo(b.ref?.key ?? '');
  });
  return visible;
}

/// One DM session row: an avatar with the label's initials via
/// [avatarInitials] and a personal-chat badge, the label as title (falling back
/// peer -> own display -> raw session id, the same chain `dm_screen` uses),
/// the localized state label as subtitle -- or, when this DM's linked peer
/// is no longer in the org roster, the revoked badge -- an `UnreadBadge`
/// when count > 0, and an onTap that navigates to the DM screen.
final class DmRailEntry extends RailEntry {
  DmRailEntry(this.session, {this.revokedOrgName, this.personalName})
      : activity = RailActivity.dm(session);

  final SessionSnapshot session;
  @override
  final String? personalName;

  @override
  final RailActivity activity;

  @override
  String searchText(AppLocalizations l) =>
      '${super.searchText(l)} ${displayName(l)} ${originalName(l)} ${activity.participantNames}';

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
    final label = displayName(l);
    return RailItem(
      kind: RailItemKind.dm,
      leading: ConversationKindAvatar(
          kind: ref.kind,
          name: label,
          online: session.state == DmSessionState.connected),
      title: label,
      timestamp: timestamp(context),
      subtitle: revokedOrgName != null
          ? l.orgRevokedBadge(revokedOrgName!)
          : preview(l) ?? dmStateLabel(l, session.state),
      // The expanded rail hides `.rail-dot`, so the badge stands alone.
      trailing: UnreadBadge(count: chrome.unreadCount),
      active: chrome.active,
      onTap: () {
        // Clear the badge + mark the conversation open first, then
        // navigate.
        chrome.onSelect?.call();
        context.go(AppRoutes.dmFor(session.sessionId));
      },
    );
  }
}

/// One channel row: leading `Icons.tag`, title `#<name>`, subtitle the
/// topic, trailing `UnreadBadge`. `onTap` opens the channel screen.
final class ChannelRailEntry extends RailEntry {
  ChannelRailEntry(this.channel, {this.personalName})
      : activity = RailActivity.channel(channel);

  final ChannelSnapshot channel;
  @override
  final String? personalName;

  @override
  final RailActivity activity;

  @override
  String searchText(AppLocalizations l) =>
      '${displayName(l)} ${channel.name} ${activity.participantNames}';

  @override
  ConversationRef get ref =>
      ConversationRef(kind: ConversationKind.channel, id: channel.name);

  @override
  Widget buildRow(BuildContext context, RailRowChrome chrome) {
    return RailItem(
      kind: RailItemKind.channel,
      leading: ConversationKindAvatar(
          kind: ref.kind, name: displayName(AppLocalizations.of(context)!)),
      title: displayName(AppLocalizations.of(context)!),
      timestamp: timestamp(context),
      // An empty topic yields no subtitle line ([RailItem] hides it).
      subtitle: preview(AppLocalizations.of(context)!) ?? channel.topic,
      trailing: UnreadBadge(count: chrome.unreadCount),
      active: chrome.active,
      onTap: () {
        chrome.onSelect?.call();
        context.go(AppRoutes.channelFor(channel.name));
      },
    );
  }
}

/// One group row: leading `Icons.group_outlined`, title the group label
/// (falling back to a shortened group id), subtitle the member count,
/// trailing `UnreadBadge`. `onTap` opens the group screen.
final class GroupRailEntry extends RailEntry {
  GroupRailEntry(this.group) : activity = RailActivity.group(group);

  final GroupSnapshot group;

  @override
  final RailActivity activity;

  @override
  String searchText(AppLocalizations l) =>
      '${group.label ?? group.groupId} ${activity.participantNames}';

  @override
  ConversationRef get ref =>
      ConversationRef(kind: ConversationKind.group, id: group.groupId);

  @override
  Widget buildRow(BuildContext context, RailRowChrome chrome) {
    final l = AppLocalizations.of(context)!;
    final label = displayName(l);
    return RailItem(
      kind: RailItemKind.group,
      leading: ConversationKindAvatar(kind: ref.kind, name: label),
      title: label,
      timestamp: timestamp(context),
      // `memberCount` is a `BigInt`; narrowing to `int` is safe for
      // realistic member counts.
      subtitle: preview(l) ?? l.membersCount(group.memberCount.toInt()),
      // The expanded rail hides `.rail-admin-crown` and `.rail-dot`
      // outright, so the badge is the only trailing element.
      trailing: UnreadBadge(count: chrome.unreadCount),
      active: chrome.active,
      onTap: () {
        chrome.onSelect?.call();
        context.go(AppRoutes.groupFor(group.groupId));
      },
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
    return RailItem(
      kind: RailItemKind.dm,
      leading: Avatar(name: fromDevice),
      title: fromDevice,
      subtitle: pending.kind == ConversationKind.channel
          ? '#${pending.host}'
          : l.onboardGroupInvite,
      semanticLabel: l.railOfferAccept(fromDevice),
      // Offer badge icon.
      trailing: Icon(
        Icons.chat_bubble_outline,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      ),
      // Beside the accept target, not inside it: two sibling buttons.
      action: IconButton(
        icon: const Icon(Icons.close, size: 16),
        tooltip: l.railOfferDismiss,
        visualDensity: VisualDensity.compact,
        onPressed: onDismiss,
      ),
      onTap: onAccept,
    );
  }
}
