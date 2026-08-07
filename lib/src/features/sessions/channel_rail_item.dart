/// Channel rail-item row -- the Flutter port of the React
/// `ChannelRailItem` (src/features/private-dm/SessionRail.tsx). Renders one
/// channel as a tappable list row: leading `Icons.tag` (React `IconHash`
/// size 18), title `#<name>` (note the `#` prefix in the title text),
/// subtitle the channel topic, and a trailing `UnreadBadge`.
///
/// `onTap` navigates to `/channel/<name>` via `context.go(AppRoutes.channelFor(name))`
/// (mirrors React `onSelect({ type: "channel", name })`). Server state for
/// the list lives in `channelListProvider`
/// (channel_group_providers.dart); the parent passes a resolved
/// `ChannelSnapshot` + the unread count.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';

/// A single channel row in the sessions rail. 1-в-1 with React's
/// `ChannelRailItem`:
///   - leading: `Icons.tag` (React `IconHash` size 18).
///   - title: `#<channel.name>` (the React strong text includes the `#`).
///   - subtitle: `channel.topic` (React renders the empty `<small>` when the
///     topic is empty, so an empty topic yields an empty subtitle line here).
///   - trailing: `UnreadBadge(count: unreadCount)` (hidden when count <= 0).
///   - Semantics mirrors React's `aria-label="Open channel ${name}"` via the
///     localized `openChannelAria(name)` ARB string.
///   - `selected` mirrors React's `rail-item-active` (the active class).
///
/// `onTap` navigates to `/channel/<name>` via `context.go(AppRoutes.channelFor(name))`
/// (mirrors React `onSelect({ type: "channel", name })`).
class ChannelRailItem extends StatelessWidget {
  const ChannelRailItem({
    super.key,
    required this.channel,
    this.active = false,
    this.unreadCount = 0,
    this.onSelect,
  });

  final ChannelSnapshot channel;
  final bool active;
  final int unreadCount;

  /// Optional select hook called BEFORE the navigate, so the parent
  /// (SessionsScreen) can clear the unread badge + set the active
  /// conversation key for this channel (mirrors React's rail `onSelect`
  /// calling `clearUnread(conversationKey(item))`). Null keeps the prior
  /// navigate-only behavior for any other caller.
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Semantics(
      label: l.openChannelAria(channel.name),
      button: true,
      selected: active,
      child: ListTile(
        leading: const Icon(Icons.tag, size: 18),
        title: Text(
          '#${channel.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(channel.topic),
        trailing: UnreadBadge(count: unreadCount),
        selected: active,
        onTap: () {
          onSelect?.call();
          context.go(AppRoutes.channelFor(channel.name));
        },
      ),
    );
  }
}
