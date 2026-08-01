/// Shared DM / message-row helpers extracted from `dm_screen.dart` and
/// `sessions_screen.dart` to keep feature screens under the 500-line
/// file-size discipline (ADR: file-size discipline). These are pure,
/// dependency-light utilities used by the DM message row and the
/// sessions list row -- previously duplicated as private helpers in each
/// screen. They are intentionally public so the screens can import the
/// shared copy and drop their local duplicates.
library;

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';

import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Delivery-tick glyph row for an own-message row. Renders nothing for
/// `failed` or null status (matches React's per-state tick rendering),
/// and shows the state glyph (`sent` -> one tick, `delivered` -> two
/// ticks, `pending` -> ellipsis) otherwise. Ported from the React
/// `MessageRow` tick span.
class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks({super.key, required this.status});

  final MessageDeliveryStatus? status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      MessageDeliveryStatus.delivered => '\u2713\u2713',
      MessageDeliveryStatus.sent => '\u2713',
      MessageDeliveryStatus.pending => '\u2026',
      MessageDeliveryStatus.failed || null => null,
    };
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
    );
  }
}

/// Locale-agnostic HH:mm clock for the sender-meta row. Returns null when
/// the message has no `sentAtMs` (matches React's `MessageTimestamp` early
/// return on a falsy epoch). Kept local + dep-free so the DM screen does
/// not pull `intl` into the widget tree -- a later atomic can swap this
/// for `DateFormat.Hm()` once a locale-aware timestamp is wanted.
String? formatClock(BigInt? sentAtMs) {
  if (sentAtMs == null) return null;
  final ms = sentAtMs.toInt();
  final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Stable per-device avatar color: a hash of the device name picks one of a
/// small fixed palette so the same sender always gets the same tint and
/// different senders usually get different tints (matching React's
/// `Avatar` behavior). Shared by the DM message row and the sessions list
/// row so both screens produce identical colors for the same label (was a
/// duplicated `_avatarColor` helper in dm_screen.dart + sessions_screen.dart;
/// consolidated here to fix that DRY violation).
Color avatarColor(String deviceName) {
  const palette = [
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.brown,
    Colors.pink,
    Colors.cyan,
    Colors.amber,
  ];
  var hash = 0;
  for (final code in deviceName.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

/// Unread-message count badge for a DM session row. 1-в-1 with React's
/// `UnreadBadge` (src/features/private-dm/SessionRail.tsx): renders nothing
/// when `count <= 0`, the literal count otherwise, and `99+` past 99. The
/// visible text is the numeral / `99+` (not localized); the `Semantics`
/// label uses the localized `unreadBadge(count)` ARB string so screen
/// readers announce `{count} unread` (en) / `{count} непрочитанных` (ru).
///
/// Styled as a small circular badge in the theme's primary color so it
/// reads as a notification indicator (mirrors React's `.unread-badge`).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final text = count > 99 ? '99+' : '$count';
    return Semantics(
      label: l.unreadBadge(count),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        constraints: const BoxConstraints(minWidth: 18),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// OpenMLS-protection badge shown in the sender-meta row of a message,
/// 1-в-1 with React's `MlsBadge`
/// (src/features/private-dm/MessageLists.tsx). Renders the literal acronym
/// `MLS` in a monospace style (the visible text is NOT localized -- it is
/// the protocol acronym, matching React's literal `MLS`). The tooltip
/// (the `message-protocol` `<code>`'s `title`) and the screen-reader label
/// (React's `aria-label="OpenMLS protected"`) are localized via the
/// `mlsBadgeTooltip` and `mlsBadgeLabel` ARB strings so the hint and the
/// a11y label follow the device locale.
///
/// Reusable: the same badge renders next to the sender name in the DM
/// `DmMessageRow` meta and (in later atomics) channel / group message
/// rows -- those React rows also embed `<MlsBadge />` in their meta.
class MlsBadge extends StatelessWidget {
  const MlsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Monospace + small to mirror React's `<code className="message-protocol">`
    // which CSS styles as a small monospace code badge.
    final base = theme.textTheme.labelSmall ?? const TextStyle();
    final style = base.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
    );
    return Semantics(
      label: l.mlsBadgeLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: l.mlsBadgeTooltip,
        child: Text('MLS', style: style),
      ),
    );
  }
}

/// Sender-meta row for the first message of a DM group: the raw
/// `fromDevice` name in bold + an [MlsBadge] + a muted locale-agnostic
/// HH:mm timestamp. 1-в-1 with the non-grouped branch of React
/// `DmMessageRow`'s `message-meta` row order
/// (`<strong>{from_device}</strong> <MlsBadge /> <MessageTimestamp/>`):
/// name, badge, timestamp. Extracted from `dm_screen.dart` to keep that
/// screen under the 500-line file-size discipline; reusable so later
/// atomics (channel / group message rows, which also embed
/// `<MlsBadge />` in their React meta) can compose the same row.
///
/// The badge renders only on non-grouped rows: callers gate this widget
/// behind their `!grouped` branch (grouped rows omit the whole meta, so
/// the badge is naturally absent there -- matching React).
class SenderMeta extends StatelessWidget {
  const SenderMeta({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = formatClock(message.sentAtMs);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              message.fromDevice,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          const MlsBadge(),
          if (clock != null) ...[
            const SizedBox(width: 6),
            Text(
              clock,
              style:
                  theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }
}
