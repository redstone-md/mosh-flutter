/// Group rail-item row -- the Flutter port of the React `GroupRailItem`
/// (src/features/private-dm/SessionRail.tsx). Renders one group as a tappable
/// list row: leading `Icons.group` (React `IconUsers` size 18), title the
/// group label (falling back to a shortened group id), subtitle the
/// member count, and a trailing admin crown + state dot + `UnreadBadge`.
///
/// Scope (this atomic): the standalone widget only. It is NOT wired into
/// `SessionsScreen` yet (a later atomic mounts the groups section), and
/// `onTap` opens `AppRoutes.groupFor(group.groupId)` (the GroupScreen route
/// shell). Server state for the list lives in `groupListProvider`
/// (channel_group_providers.dart); the parent passes a resolved
/// `GroupSnapshot` + the unread count.
library;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/features/sessions/state_dot.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/util/format.dart';

/// A single group row in the sessions rail. 1-в-1 with React's
/// `GroupRailItem`:
///   - leading: `Icons.group` (React `IconUsers` size 18).
///   - title: the group label, falling back to `shorten(group.groupId, 6)`
///     (React `group.label ?? shorten(group.group_id, 6)`).
///   - subtitle: `${memberCount} members` via the localized `membersCount`
///     ARB string (React `String(group.member_count)`); `memberCount` is a
///     `BigInt`, narrowed to `int` here (safe for realistic member counts).
///   - trailing (in order): an admin crown `Icons.workspace_premium` (React
///     `IconCrown` size 11) with a `Tooltip` using `groupAdminBadge` when
///     `isAdmin`; the `StateDot(state: group.state)` (React
///     `rail-dot rail-dot-${group.state}`); and `UnreadBadge(count: ...)`.
///   - Semantics mirrors React's `aria-label="Open group ${label}"` via the
///     localized `openGroupAria(label)` ARB string.
///   - `selected` mirrors React's `rail-item-active` (the active class).
///
/// `onTap` is a no-op: there is no group screen route yet. The navigation
/// `onTap` opens `AppRoutes.groupFor(group.groupId)` (the GroupScreen route
/// shell), mirroring React's `onSelect({ type: "group", id })`.
class GroupRailItem extends StatelessWidget {
  const GroupRailItem({
    super.key,
    required this.group,
    this.active = false,
    this.unreadCount = 0,
  });

  final GroupSnapshot group;
  final bool active;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final label = group.label ?? shorten(group.groupId, 6);
    return Semantics(
      label: l.openGroupAria(label),
      button: true,
      selected: active,
      child: ListTile(
        leading: const Icon(Icons.group, size: 18),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(l.membersCount(group.memberCount.toInt())),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (group.isAdmin)
              Tooltip(
                message: l.groupAdminBadge,
                child: const Icon(Icons.workspace_premium, size: 14),
              ),
            StateDot(state: group.state),
            const SizedBox(width: 8),
            UnreadBadge(count: unreadCount),
          ],
        ),
        selected: active,
        // Open the group screen for this group (mirrors React
        // `onSelect({ type: "group", id })`). Keyed by `groupId` (the group
        // identity), not a name.
        onTap: () => context.go(AppRoutes.groupFor(group.groupId)),
      ),
    );
  }
}
