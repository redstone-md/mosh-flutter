/// Small helpers shared by every conversation: chat header sizing, message
/// meta styles, avatar colours and initials. DM, channel and org group all
/// use them, as does the sessions list.
///
/// They live here so the screens stay under the 500-line file-size
/// discipline (ADR: file-size discipline) and share one copy instead of
/// keeping private duplicates.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;

import 'package:mosh/src/rust/outbound_delivery.dart';

/// Gap between sender name and timestamp in a message meta row.
const double kMessageMetaGap = 8;

/// Avatar width in a message row. The real `CircleAvatar` and the spacer on
/// a grouped row both use it, so grouped rows line up under the first row's
/// avatar.
const double messageAvatarSize = 32;

/// Chat headers are compact under 640px wide: 54px min-height, a 14px
/// title and an 11px subtitle 2px under it (vs 15px/12px at 4px).
bool _isCompactChatHeader(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 640;

/// Toolbar height for a chat AppBar: 70px desktop, 54 under the 640px
/// breakpoint.
double chatHeaderHeight(BuildContext context) =>
    _isCompactChatHeader(context) ? 54 : 70;

/// Chat title: 15px/700, 14px on a narrow header.
TextStyle chatTitleStyle(BuildContext context) => TextStyle(
      fontSize: _isCompactChatHeader(context) ? 14 : 15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: MoshColors.fg1,
    );

/// Chat subtitle: 12px fg-3, 11px on a narrow header.
TextStyle chatSubtitleStyle(BuildContext context) => TextStyle(
      fontSize: _isCompactChatHeader(context) ? 11 : 12,
      color: MoshColors.fg3,
    );

/// The gap under the title: 4px, 2px when compact.
double chatSubtitleGap(BuildContext context) =>
    _isCompactChatHeader(context) ? 2 : 4;

/// Gap from avatar to body in a message row.
const double kMessageRowGap = 12;

/// The message list's own padding, shared by the DM, channel and group
/// lists.
const EdgeInsets kChatScrollPadding =
    EdgeInsets.symmetric(horizontal: 22, vertical: 16);

/// Vertical lead-in for a message row: a continuation sits 6px under its
/// predecessor (grouped), a fresh sender 12px under.
double messageRowSpacing(bool grouped) => grouped ? 6 : 12;

/// Sender name in a message meta row: 13px bold fg-1.
const TextStyle kMessageMetaNameStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w700,
  color: MoshColors.fg1,
);

/// Timestamp in a message meta row: 11px fg-4.
const TextStyle kMessageTimeStyle =
    TextStyle(fontSize: 11, color: MoshColors.fg4);

/// The message text itself: 13.5px at 1.5 line height in fg-1.
const TextStyle kMessageBodyStyle =
    TextStyle(fontSize: 13.5, height: 1.5, color: MoshColors.fg1);

/// Delivery-tick glyph row for an own-message row. Renders nothing for
/// `failed` or null status, and shows the state glyph (`sent` -> one tick,
/// `delivered` -> two ticks, `pending` -> ellipsis, `queued` -> a clock)
/// otherwise.
///
/// [read] is the [[Read receipt]]: when true the SAME two ticks change
/// color (never a third tick) — the counterpart's authenticated receipt
/// landed, so the delivered marks read as "seen". The label stays
/// "delivered"; the color carries the read fact.
class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks({super.key, required this.status, this.read = false});

  final MessageDeliveryStatus? status;

  /// Whether the counterpart's read receipt has landed on this message.
  final bool read;

  @override
  Widget build(BuildContext context) {
    // Localized full label: "✓✓ delivered" / "✓ sent" / "sending…". The
    // visible text IS the label (glyph + word). A queued message has no
    // glyph in the font, so it draws a clock icon in front of its word.
    final l = AppLocalizations.of(context)!;
    final label = switch (status) {
      MessageDeliveryStatus.delivered => l.deliveryDelivered,
      MessageDeliveryStatus.sent => l.deliverySent,
      MessageDeliveryStatus.pending => l.deliverySending,
      MessageDeliveryStatus.queued => l.deliveryQueued,
      MessageDeliveryStatus.failed || null => null,
    };
    if (label == null) return const SizedBox.shrink();
    // The read receipt changes the COLOR of the same glyphs, never adds a
    // third tick: the delivered marks carry the theme's accent instead of
    // the faint fg-4, exactly like a "seen" mark.
    final style = read
        ? const TextStyle(fontSize: 10, color: MoshColors.moss)
        : const TextStyle(fontSize: 10, color: MoshColors.fg4);
    // 10px fg-4, 1px below the meta line.
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      // The label already includes the glyph + word, so the a11y string is
      // "Delivery: ✓✓ delivered" etc.
      child: Semantics(
        label: 'Delivery: $label',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == MessageDeliveryStatus.queued)
              const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Icon(Icons.schedule, size: 10, color: MoshColors.fg4),
              ),
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}

/// Locale-aware HH:mm clock for the sender-meta row. Formats the epoch in
/// the LOCAL timezone via `intl`'s `DateFormat.Hm(locale)` so the
/// hour/minute follow the device locale. Returns null when the message
/// has no `sentAtMs`. `locale` defaults to `'en'` and is fed by the
/// `AppLocalizations` locale in [ConversationSenderMeta]; callers must
/// `initializeDateFormatting()` once in `main()` for non-en locales to
/// format in-locale rather than fall back to en.
String? formatClock(BigInt? sentAtMs, {String? locale}) {
  if (sentAtMs == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(sentAtMs.toInt()).toLocal();
  return DateFormat.Hm(locale ?? 'en').format(dt);
}

/// Full locale-aware date-time string for the sender-meta timestamp's
/// tooltip (the hover tooltip). Renders a full date + time in the LOCAL
/// timezone via `DateFormat.yMMMd(locale).add_Hm()` -- e.g. "Aug 1, 2026
/// 2:30 PM" (en). Returns null when the message has no `sentAtMs`.
/// `locale` defaults to `'en'` and mirrors [formatClock]'s locale
/// handling.
String? formatClockFull(BigInt? sentAtMs, {String? locale}) {
  if (sentAtMs == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(sentAtMs.toInt()).toLocal();
  // add_Hm() appends the Hm skeleton to the locale-aware yMMMd DateFormat;
  // the locale is already set on the base, so add_Hm takes no locale arg.
  return DateFormat.yMMMd(locale ?? 'en').add_Hm().format(dt);
}

/// Avatar initials: split the name on whitespace/underscore/dash, take the
/// first char of each part, drop empties (leading/trailing separators
/// yield empty parts), join, keep at most 2 chars, uppercase; return `"?"`
/// when the result is empty. Sibling of [avatarColor]: the DM message row
/// and the sessions list row both render an avatar with initials, so the
/// algorithm lives here once (DRY) and both screens call this --
/// previously each call site rendered only the first char
/// (`label[0].toUpperCase()`), which lost the second initial of compound
/// names (e.g. `juno-phone` rendered `J` instead of `JP`).
String avatarInitials(String name) {
  final parts = name.split(RegExp(r'[\s_-]+'));
  // Drop the empty strings that a leading/trailing/multiple separator
  // produces, then take the first char of each surviving part.
  final initials = parts.where((p) => p.isNotEmpty).map((p) => p[0]).join();
  // Keep at most 2 initials. A plain UTF-16 slice is fine here: the initials
  // are first chars of ASCII-ish device/label strings.
  final capped = initials.length >= 2 ? initials.substring(0, 2) : initials;
  return capped.isEmpty ? '?' : capped.toUpperCase();
}

/// Unread-message count badge for a DM session row: renders nothing when
/// `count <= 0`, the literal count otherwise, and `99+` past 99. The
/// visible text is the numeral / `99+` (not localized); the `Semantics`
/// label uses the localized `unreadBadge(count)` ARB string so screen
/// readers announce `{count} unread` (en) / `{count} непрочитанных` (ru).
///
/// Styled as a small circular badge in the theme's primary color so it
/// reads as a notification indicator.
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
          // The theme's on-accent ink (mossInk): white on the moss primary
          // fails contrast at ~1.6:1 (audit 2026-09-21). Live number ->
          // tabular figures keep the badge from jittering as the count ticks.
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: kLiveNumberFontFeatures,
          ),
        ),
      ),
    );
  }
}

/// OpenMLS-protection badge shown in the sender-meta row of a message.
/// Renders the literal acronym `MLS` in a monospace style (the visible
/// text is NOT localized -- it is the protocol acronym). The tooltip and
/// the screen-reader label are localized via the `mlsBadgeTooltip` and
/// `mlsBadgeLabel` ARB strings so the hint and the a11y label follow the
/// device locale.
///
/// Reusable: the same badge renders next to the sender name in the DM
/// `DmMessageRow` meta and (in later atomics) channel / group message
/// rows.
class MlsBadge extends StatelessWidget {
  const MlsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Monospace 13px in the window's fg-1, like a bare inline code span.
    const style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: MoshColors.fg1,
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
