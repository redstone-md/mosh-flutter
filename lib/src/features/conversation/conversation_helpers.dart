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
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/modal_focus_trap.dart';

import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/util/format.dart' show shorten;

/// React `.message-meta { gap: 8px }`.
const double kMessageMetaGap = 8;

/// Avatar width in a message row. The real `CircleAvatar` and the spacer on
/// a grouped row both use it, so grouped rows line up under the first row's
/// avatar (React's `avatar avatar-spacer`).
const double messageAvatarSize = 32;

/// React `.chat-header` is 14/22 padding around a 15px/700 title with a
/// 12px --fg-3 subtitle 4px under it. Its `@media (max-width: 640px)` rule
/// shrinks the whole block: `min-height: 54px`, `h1 { font-size: 14px }`,
/// `p { margin-top: 2px; font-size: 11px }`.
bool _isCompactChatHeader(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= 640;

/// Toolbar height for a chat AppBar: React's 70px desktop header, 54 under
/// the 640px breakpoint.
double chatHeaderHeight(BuildContext context) =>
    _isCompactChatHeader(context) ? 54 : 70;

/// `.chat-title-block h1` -- 15px/700 at 0.02em, 14px on a narrow header.
TextStyle chatTitleStyle(BuildContext context) => TextStyle(
      fontSize: _isCompactChatHeader(context) ? 14 : 15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: MoshColors.fg1,
    );

/// `.chat-title-block p` -- 12px --fg-3, 11px on a narrow header.
TextStyle chatSubtitleStyle(BuildContext context) => TextStyle(
      fontSize: _isCompactChatHeader(context) ? 11 : 12,
      color: MoshColors.fg3,
    );

/// The gap under the title: `margin-top: 4px`, 2px when compact.
double chatSubtitleGap(BuildContext context) =>
    _isCompactChatHeader(context) ? 2 : 4;

/// React `.message-row { gap: 12px }` -- avatar to body.
const double kMessageRowGap = 12;

/// React `.chat-scroll { padding: 16px 22px }` -- the message list's own
/// padding, shared by the DM, channel and group lists.
const EdgeInsets kChatScrollPadding =
    EdgeInsets.symmetric(horizontal: 22, vertical: 16);

/// Vertical lead-in for a message row. React stacks rows with
/// `.message-stack { gap: 12px }` and pulls a grouped row back up with
/// `.message-row-grouped { margin-top: -6px }`, so a continuation sits 6px
/// under its predecessor and a fresh sender sits 12px under.
double messageRowSpacing(bool grouped) => grouped ? 6 : 12;

/// React `.message-meta strong { font-size: 13px; color: var(--fg-1) }`
/// (`<strong>` carries the UA bold weight).
const TextStyle kMessageMetaNameStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w700,
  color: MoshColors.fg1,
);

/// React `.message-time { color: var(--fg-4); font-size: 11px }`.
const TextStyle kMessageTimeStyle =
    TextStyle(fontSize: 11, color: MoshColors.fg4);

/// React `.message-body p { font-size: 13.5px; line-height: 1.5;
/// color: var(--fg-1) }` -- the message text itself.
const TextStyle kMessageBodyStyle =
    TextStyle(fontSize: 13.5, height: 1.5, color: MoshColors.fg1);

/// React `.device-fp` -- the shortened fingerprint chip in a multi-party
/// sender meta: `font-family: mono; font-size: 10px; color: var(--fg-4);
/// padding: 2px 5px; border-radius: 4px; background: var(--bg-2)`.
class DeviceFingerprintChip extends StatelessWidget {
  const DeviceFingerprintChip({super.key, required this.fingerprint});

  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: MoshColors.bg2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        shorten(fingerprint, 6),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: MoshColors.fg4,
        ),
      ),
    );
  }
}

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
    // Localized full label, 1-в-1 with React`s DeliveryTicks visible text
    // (src/features/private-dm/MessageLists.tsx): "✓✓ delivered" / "✓ sent" /
    // "sending…". The visible text IS the label (glyph + word), matching
    // React`s <small>{label}</small>.
    final l = AppLocalizations.of(context)!;
    final label = switch (status) {
      MessageDeliveryStatus.delivered => l.deliveryDelivered,
      MessageDeliveryStatus.sent => l.deliverySent,
      MessageDeliveryStatus.pending => l.deliverySending,
      MessageDeliveryStatus.failed || null => null,
    };
    if (label == null) return const SizedBox.shrink();
    // React `.delivery-ticks { font-size: 10px; color: var(--fg-4);
    // margin-top: 1px }`.
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      // `Semantics(label: 'Delivery: $label')` mirrors React`s
      // `aria-label={`Delivery: ${label}`}` (label already includes the
      // glyph + word, so the a11y string is "Delivery: ✓✓ delivered" etc.).
      child: Semantics(
        label: 'Delivery: $label',
        excludeSemantics: true,
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, color: MoshColors.fg4),
        ),
      ),
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
    // React renders a bare `<code class="message-protocol">` with NO CSS
    // rule of its own, so it lands on the UA `code` default: the browser
    // fixed font at 13px, inheriting `.mosh-window`'s --fg-1.
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
    // AppLocalizations drives the DateFormat locale (en/ru); falls back to
    // en when the delegate is absent (e.g. a bare unit test harness).
    final locale = AppLocalizations.of(context)?.localeName;
    final clock = formatClock(message.sentAtMs, locale: locale);
    final full = formatClockFull(message.sentAtMs, locale: locale);
    // React `.message-meta { gap: 8px; margin-bottom: 2px; align-items:
    // baseline }` with `strong { font-size: 13px; color: --fg-1 }`.
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              message.fromDevice,
              style: kMessageMetaNameStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: kMessageMetaGap),
          const MlsBadge(),
          if (clock != null && full != null) ...[
            const SizedBox(width: kMessageMetaGap),
            Tooltip(
              // Mirrors React's `title={date.toLocaleString()}` on the
              // `<time>` element: the full locale-aware date-time shows on
              // hover (desktop) / long-press (mobile).
              message: full,
              child: Text(clock, style: kMessageTimeStyle),
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
    this.peer,
    this.showMlsBadge = true,
  });

  final String fromDevice;
  final String fromFingerprint;
  final BigInt? sentAtMs;

  /// Optional per-conversation peer actions (React `PeerActions` in
  /// MessageLists.tsx:31-35). `null` (the default) renders `fromDevice`
  /// as plain bold `Text` -- the DM-row + existing-tests case. When set
  /// and `fromFingerprint != peer.ownFingerprint`, the name becomes a
  /// tappable target opening the [_PeerNickname] popover (React's
  /// `nick-popover`, role="dialog"). When set and the row IS the user's
  /// own fingerprint, the name stays plain bold (React `<strong>{name}</strong>`).
  final PeerActions? peer;
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
    // React PeerNickname (MessageLists.tsx:198-244): own fingerprint ->
    // plain `<strong>{name}</strong>`; a non-own name -> a tappable
    // nick-button opening a nick-popover. `peer == null` reproduces the
    // DM-row + existing-tests behavior (plain bold, no tap target).
    final nameWidget = _peerName(context, theme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: nameWidget),
          const SizedBox(width: kMessageMetaGap),
          DeviceFingerprintChip(fingerprint: fromFingerprint),
          if (showMlsBadge) ...[
            const SizedBox(width: kMessageMetaGap),
            const MlsBadge(),
          ],
          if (clock != null && full != null) ...[
            const SizedBox(width: kMessageMetaGap),
            Tooltip(
              message: full,
              child: Text(clock, style: kMessageTimeStyle),
            ),
          ],
        ],
      ),
    );
  }

  /// Renders the `fromDevice` name. When `peer == null` (DM row +
  /// existing tests) OR `fromFingerprint == peer.ownFingerprint` (own
  /// name), it is plain bold `Text` (React `<strong>{name}</strong>`).
  /// Otherwise it wraps the same bold `Text` in a tap target that opens
  /// the [_PeerNickname] popover (React `nick-button` + `nick-popover`).
  Widget _peerName(BuildContext context, ThemeData theme) {
    final text = Text(
      fromDevice,
      style: kMessageMetaNameStyle,
      overflow: TextOverflow.ellipsis,
    );
    final p = peer;
    if (p == null || fromFingerprint == p.ownFingerprint) return text;
    return _PeerNickname(
      name: fromDevice,
      fingerprint: fromFingerprint,
      peer: p,
      child: text,
    );
  }
}

/// The peer-actions value object mirroring React's `PeerActions` type
/// (src/features/private-dm/MessageLists.tsx:31-35):
/// ownFingerprint, offered (a Set of offered fingerprints), busy, and an
/// onMessage fingerprint callback. Co-located with
/// [MultiPartySenderMeta] (the only consumer) because both channel + group
/// rows use it (DRY): the screens construct it from their state and thread
/// it down through [ChannelMessageRow] / [GroupMessageRow] into the meta.
///
/// `offered` is the set of fingerprints the user already messaged this
/// session (React's `offeredFingerprints` in use-dm-offers.ts); it is reset
/// when the active host changes (the screen owns that reset). `busy` is the
/// offer-in-flight flag (React's `offerBusy`). `onMessage` is the closure
/// that creates a DM invite, sends the offer over the channel/group, marks
/// the fingerprint offered, and navigates to the new DM (React
/// `use-dm-offers.ts:54` `offerDm`).
@immutable
class PeerActions {
  const PeerActions({
    required this.ownFingerprint,
    required this.offered,
    required this.busy,
    required this.onMessage,
  });

  /// The user's own device fingerprint -- a name with this fingerprint
  /// renders as plain bold (React `fingerprint === peer.ownFingerprint`).
  final String ownFingerprint;

  /// Fingerprints already messaged this session -- a name in this set
  /// disables the "Message" button and relabels it "Invite sent" (React
  /// `alreadyOffered = peer.offered.has(fingerprint)`).
  final Set<String> offered;

  /// True while a DM-offer send is in flight -- disables the "Message"
  /// button (React `disabled={alreadyOffered || peer.busy}`).
  final bool busy;

  /// Opens a 1:1 DM with the named peer (React `peer.onMessage(fingerprint)`).
  /// The screen wires this to `gateway.createInvite` +
  /// `sendChannelDmOffer`/`sendGroupDmOffer`, tracks the fingerprint as
  /// offered, and navigates to the new DM session.
  final Future<void> Function(String peerFingerprint) onMessage;
}

/// The nick-popover anchor + popover (React `PeerNickname`'s `nick-anchor`
/// + `nick-popover`, MessageLists.tsx:198-244). Wraps the bold name `Text`
/// (passed as [child]) in an `InkWell` tap target; tapping opens a small
/// `Dialog` (Flutter's idiomatic `role="dialog"` equivalent) titled with the
/// peer's name and a "Message" button that is disabled when the peer is
/// already offered OR the screen is busy, labelled "Invite sent" when
/// already offered, and otherwise calls [PeerActions.onMessage] then
/// closes the popover.
///
/// The visible name is the SAME bold `Text` the plain-bold branch renders
/// (passed in as [child]) so the meta row's typography is byte-identical
/// whether the name is tappable or plain -- the only delta is the tap
/// target wrapper, matching React where the `nick-button` carries the
/// identical bold style.
class _PeerNickname extends StatelessWidget {
  const _PeerNickname({
    required this.name,
    required this.fingerprint,
    required this.peer,
    required this.child,
  });

  final String name;
  final String fingerprint;
  final PeerActions peer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final alreadyOffered = peer.offered.contains(fingerprint);
    return InkWell(
      onTap: () => _show(context, l, alreadyOffered),
      borderRadius: BorderRadius.circular(4),
      child: child,
    );
  }

  // Opens the Dialog popover. React renders `nick-popover` inline below the
  // name; Flutter's `showDialog` with an `AlertDialog` is the idiomatic
  // equivalent of a `role="dialog"` overlay and handles the backdrop + Esc
  // dismiss (React's `nick-popover-backdrop` onClick + Esc semantics).
  Future<void> _show(
      BuildContext context, AppLocalizations l, bool alreadyOffered) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ModalFocusTrap(
        child: AlertDialog(
          title: Text(name),
          // The Message button mirrors React's `nick-popover` primary button:
          // disabled when alreadyOffered || busy, labelled "Invite sent" when
          // already offered, otherwise "Message". Tapping it calls
          // `peer.onMessage(fingerprint)` then closes the popover (React
          // `peer.onMessage(fingerprint); setOpen(false)`).
          actions: [
            TextButton(
              onPressed: (alreadyOffered || peer.busy)
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      peer.onMessage(fingerprint);
                    },
              child:
                  Text(alreadyOffered ? l.peerInviteSent : l.peerMessageAction),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l.dialogCancel),
            ),
          ],
        ),
      ),
    );
  }
}
