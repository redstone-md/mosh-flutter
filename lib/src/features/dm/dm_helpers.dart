/// Shared DM / message-row helpers extracted from `dm_screen.dart` and
/// `sessions_screen.dart` to keep feature screens under the 500-line
/// file-size discipline (ADR: file-size discipline). These are pure,
/// dependency-light utilities used by the DM message row and the
/// sessions list row -- previously duplicated as private helpers in each
/// screen. They are intentionally public so the screens can import the
/// shared copy and drop their local duplicates.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mosh/l10n/app_localizations.dart';

import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/util/format.dart' show shorten;

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
          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
    );
  }
}

/// Locale-aware HH:mm clock for the sender-meta row, 1-в-1 with React's
/// `MessageTimestamp` visible text
/// (`date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })`).
/// Formats the epoch in the LOCAL timezone (matching JS `toLocaleTimeString`,
/// which renders in the host's local tz) via `intl`'s `DateFormat.Hm(locale)`
/// so the hour/minute follow the device locale. Returns null when the message
/// has no `sentAtMs` (matches React's early return on a falsy epoch). `locale`
/// defaults to `'en'` and is fed by the `AppLocalizations` locale in
/// [SenderMeta]; callers must `initializeDateFormatting()` once in `main()`
/// for non-en locales to format in-locale rather than fall back to en.
String? formatClock(BigInt? sentAtMs, {String? locale}) {
  if (sentAtMs == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(sentAtMs.toInt()).toLocal();
  return DateFormat.Hm(locale ?? 'en').format(dt);
}

/// Full locale-aware date-time string for the sender-meta timestamp's
/// tooltip, 1-в-1 with React's `MessageTimestamp`
/// `title={date.toLocaleString()}` attribute (the hover tooltip). Renders a
/// full date + time in the LOCAL timezone via
/// `DateFormat.yMMMd(locale).add_Hm()` -- e.g. "Aug 1, 2026 2:30 PM"
/// (en). Returns null when the message has no `sentAtMs` (matches React's
/// early return on a falsy epoch). `locale` defaults to `'en'` and mirrors
/// [formatClock]'s locale handling.
String? formatClockFull(BigInt? sentAtMs, {String? locale}) {
  if (sentAtMs == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(sentAtMs.toInt()).toLocal();
  // add_Hm() appends the Hm skeleton to the locale-aware yMMMd DateFormat;
  // the locale is already set on the base, so add_Hm takes no locale arg.
  return DateFormat.yMMMd(locale ?? 'en').add_Hm().format(dt);
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

/// React `Avatar` initials (src/features/private-dm/Avatar.tsx): split the
/// name on whitespace/underscore/dash, take the first char of each part,
/// drop empties (leading/trailing separators yield empty parts), join,
/// keep at most 2 chars, uppercase; return `"?"` when the result is empty
/// (mirrors React's `initials || "?"` fallback). Sibling of [avatarColor]:
/// the DM message row and the sessions list row both render an avatar with
/// initials, so the algorithm lives here once (DRY) and both screens call
/// this -- previously each call site rendered only the first char
/// (`label[0].toUpperCase()`), a parity gap that lost the second initial of
/// compound names (e.g. `juno-phone` rendered `J` instead of `JP`).
String avatarInitials(String name) {
  final parts = name.split(RegExp(r'[\s_-]+'));
  // `.where((p) => p.isNotEmpty)` drops the empty strings that a
  // leading/trailing/multiple separator produces (React's `.filter(Boolean)`),
  // then take the first char of each surviving part (React's `.map(p => p[0])`).
  final initials = parts.where((p) => p.isNotEmpty).map((p) => p[0]).join();
  // `.substring(0, min(2, len))` mirrors React's `.slice(0, 2)` (max 2
  // initials) without the `characters` package for grapheme splitting -- the
  // initials are first chars of ASCII-ish device/label strings, so a UTF-16
  // code-unit slice matches React's JS string slice.
  final capped = initials.length >= 2 ? initials.substring(0, 2) : initials;
  return capped.isEmpty ? '?' : capped.toUpperCase();
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
/// `fromDevice` name in bold + an [MlsBadge] + a muted locale-aware HH:mm
/// timestamp wrapped in a [Tooltip] with the full locale-aware date-time
/// (the React `MessageTimestamp` `title={date.toLocaleString()}`). 1-в-1
/// with the non-grouped branch of React
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
    // AppLocalizations drives the DateFormat locale (en/ru); falls back to
    // en when the delegate is absent (e.g. a bare unit test harness).
    final locale = AppLocalizations.of(context)?.localeName;
    final clock = formatClock(message.sentAtMs, locale: locale);
    final full = formatClockFull(message.sentAtMs, locale: locale);
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
          if (clock != null && full != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              // Mirrors React's `title={date.toLocaleString()}` on the
              // `<time>` element: the full locale-aware date-time shows on
              // hover (desktop) / long-press (mobile).
              message: full,
              child: Text(
                clock,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sender-meta row for the FIRST message of a channel / group group: the
/// raw `fromDevice` name in bold + a monospace shortened `fromFingerprint`
/// + an [MlsBadge] + a muted locale-aware HH:mm timestamp wrapped in a
/// [Tooltip] with the full locale-aware date-time. 1-1 with the non-grouped
/// branch of React `ChannelMessageRow` / `GroupMessageRow`'s `message-meta`
/// row order
/// (`<PeerNickname/><code className="device-fp">{shorten(from_fingerprint,6)}</code><MlsBadge/><MessageTimestamp/>`):
/// name, fingerprint, badge, timestamp.
///
/// Differs from [SenderMeta] (the DM meta): the DM meta has NO fingerprint
/// code (DMs are 1:1, so the device name alone disambiguates the single
/// peer), whereas channel / group meta render the shortened fingerprint
/// because those contexts are multi-party and two members could share a
/// display name but never a device fingerprint (React's `<code
/// className="device-fp">` in `ChannelMessageRow` / `GroupMessageRow`).
/// This concrete difference is why this is a sibling widget rather than a
/// reuse of [SenderMeta] -- per the brief: reuse `SenderMeta` directly
/// unless React's channel/group meta differs (it does, by the fingerprint
/// code).
///
/// Takes primitive ctor args (`fromDevice`, `fromFingerprint`, `sentAtMs`)
/// rather than a `ChannelMessage` / `GroupMessage` so it stays decoupled
/// from the two distinct generated message types (which share no base) --
/// both `ChannelMessageRow` (channel_message_row.dart) and `GroupMessageRow`
/// (group_message_row.dart) feed it their row's three fields. The visible
/// fingerprint text uses [shorten] (the same helper DMs use for their
/// fingerprint badges), with `head = 6` to match React's
/// `shorten(message.from_fingerprint, 6)`.
class MultiPartySenderMeta extends StatelessWidget {
 const MultiPartySenderMeta({
   super.key,
   required this.fromDevice,
   required this.fromFingerprint,
   required this.sentAtMs,
    this.showMlsBadge = true,
 });

 final String fromDevice;
 final String fromFingerprint;
 final BigInt? sentAtMs;
  // React distinguishes channel vs group sender-meta: the GROUP row
  // (MessageLists.tsx GroupMessageRow ~line 273-279) renders an MLS badge
  // after the fingerprint code; the CHANNEL row (ChannelMessageRow ~line
  // 378-383) does NOT. Default true matches the group layout; channel
  // passes false.
  final bool showMlsBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = AppLocalizations.of(context)?.localeName;
    final clock = formatClock(sentAtMs, locale: locale);
    final full = formatClockFull(sentAtMs, locale: locale);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              fromDevice,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            shorten(fromFingerprint, 6),
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.hintColor,
            ),
          ),
         const SizedBox(width: 6),
          if (showMlsBadge) ...[
            const SizedBox(width: 6),
            const MlsBadge(),
          ],
         if (clock != null && full != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: full,
              child: Text(
                clock,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
