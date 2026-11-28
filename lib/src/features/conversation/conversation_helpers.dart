import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;
import 'package:mosh/src/features/conversation/message_tone.dart';

import 'package:mosh/src/rust/outbound_delivery.dart';

/// Gap between the sender's name and the fingerprint beside it.
const double kMessageMetaGap = MoshSpace.s2;

/// Avatar width in a message row of a group or a channel. The avatar and
/// the gutter kept under it on the later rows of a run both use it.
const double messageAvatarSize = MoshSpace.s8;

/// Height of the bar at the top of a conversation and of the panel beside
/// it: the Top bar card's 64 px.
const double kChatHeaderHeight = MoshSpace.s16;

/// Width of the panel beside a conversation on the desktop: its details and
/// its connection status.
const double kConversationPanelWidth = 360;

/// Gap from the avatar's gutter to the bubble.
const double kMessageRowGap = MoshSpace.s2;

/// The measure of a bubble's text: a long link or a token without spaces
/// breaks inside it.
double messageMeasure({required bool compact}) => compact ? 232 : 480;

/// Width of a file or a picture in a bubble. A caption under it wraps at
/// this width, as the bubble is no wider than the card; on the phone it is
/// the width of a line of text.
double attachmentWidth({required bool compact}) => compact
    ? messageMeasure(compact: true) + MoshShapes.bubbleInset.horizontal
    : 320;

/// The feed's own padding, shared by the DM, channel and group lists: 12 px
/// at the sides on the phone, 20 px on the desktop.
EdgeInsets feedPadding({required bool compact}) => EdgeInsets.symmetric(
    horizontal: compact ? MoshSpace.s3 : MoshSpace.s5, vertical: MoshSpace.s4);

/// Vertical lead-in for a message row: bubbles of one run sit 4 px apart
/// and a new run starts 12 px lower.
double messageRowSpacing(bool grouped) => grouped ? MoshSpace.s1 : MoshSpace.s3;

/// Half the 4 px gap every neighbour in the feed keeps from the next; a row
/// that starts a run adds its lead-in to it. A message row keeps the half
/// above and below its bubble, a divider is given it by the list, and the
/// list's own padding is shorter by it, so the feed ends [feedPadding] from
/// its last bubble.
const double kFeedHalfGap = MoshSpace.s1 / 2;

/// The box a delivery mark takes beside the time, whatever its glyph.
const double kDeliveryMarkSize = MoshSpace.s4;

/// The message text itself.
TextStyle messageBodyStyle(BuildContext context, MessageTone tone) =>
    Theme.of(context).textTheme.bodyLarge!.copyWith(color: tone.ink);

/// The time of a message, and the other quiet lines of its size.
TextStyle messageTimeStyle(BuildContext context, MessageTone tone) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(color: tone.quiet);

/// The Delivery ticks card, beside the time of a message the user sent: a
/// clock while the message is queued or on its way, one tick once it is
/// sent, two once it is delivered. Renders nothing for `failed` or null.
///
/// [read] is the [[Read receipt]]: the same pair of ticks, never a third,
/// drawn heavier and in the darker ink, as a colour alone is too close on
/// the bubble. The label stays "delivered".
class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks(
      {super.key, required this.status, required this.tone, this.read = false});

  final MessageDeliveryStatus? status;
  final MessageTone tone;

  /// Whether the counterpart's read receipt has landed on this message.
  final bool read;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final label = switch (status) {
      MessageDeliveryStatus.delivered => l.deliveryDelivered,
      MessageDeliveryStatus.sent => l.deliverySent,
      MessageDeliveryStatus.pending => l.deliverySending,
      MessageDeliveryStatus.queued => l.deliveryQueued,
      MessageDeliveryStatus.failed || null => null,
    };
    if (label == null) return const SizedBox.shrink();
    // Each of the paired ticks is drawn smaller than a lone one, so the
    // lone tick and the clock are set a step down.
    final (icon, size) = switch (status) {
      MessageDeliveryStatus.delivered => (
          read ? MoshIcons.doneAllRead : MoshIcons.doneAll,
          MoshSpace.s4
        ),
      MessageDeliveryStatus.sent => (MoshIcons.check, MoshSpace.s3),
      _ => (MoshIcons.schedule, MoshSpace.s3),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: kDeliveryMarkSize,
          child: Center(
            child: Icon(icon, size: size, color: read ? tone.ink : tone.quiet),
          ),
        ),
      ),
    );
  }
}

DateTime? messageDate(BigInt? sentAtMs) => sentAtMs == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(sentAtMs.toInt()).toLocal();

/// Locale-aware HH:mm clock of a message, as its footer shows it. Formats
/// the epoch in the LOCAL timezone via `intl`'s `DateFormat.Hm(locale)` so
/// the hour/minute follow the device locale. Returns null when the message
/// has no `sentAtMs`. `locale` defaults to `'en'` and is fed by the
/// `AppLocalizations` locale; callers must
/// `initializeDateFormatting()` once in `main()` for non-en locales to
/// format in-locale rather than fall back to en.
String? formatClock(BigInt? sentAtMs, {String? locale}) {
  if (sentAtMs == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(sentAtMs.toInt()).toLocal();
  return DateFormat.Hm(locale ?? 'en').format(dt);
}

/// Full locale-aware date-time string for the tooltip of a message's time.
/// Renders a full date + time in the LOCAL timezone via `DateFormat.yMMMd(locale).add_Hm()` -- e.g. "Aug 1, 2026
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

String avatarInitials(String name) {
  final parts = name.split(RegExp(r'[\s_-]+'));
  // Drop the empty strings that a leading/trailing/multiple separator
  // produces, then take the first character of each surviving part, at most
  // two. Characters, not UTF-16 units: half an emoji cannot be painted.
  final initials = parts
      .where((p) => p.isNotEmpty)
      .map((p) => p.characters.first)
      .take(2)
      .join();
  return initials.isEmpty ? '?' : initials.toUpperCase();
}

/// Unread-message count badge for a DM session row: renders nothing when
/// `count <= 0`, the literal count otherwise, and `99+` past 99. The
/// visible text is the numeral / `99+` (not localized); the `Semantics`
/// label uses the localized `unreadBadge(count)` ARB string so screen
/// readers announce `{count} unread` (en) / `{count} непрочитанных` (ru).
///
/// The Unread badge card: a 20 px pill in the primary colour.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = MoshColors.of(context);
    final text = count > 99 ? '99+' : '$count';
    return Semantics(
      label: l.unreadBadge(count),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(
            minWidth: MoshSpace.s5, minHeight: MoshSpace.s5),
        padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s1),
        decoration:
            ShapeDecoration(color: colors.primary, shape: MoshShapes.pill),
        // The badge hugs its count wherever a row puts it. A live number:
        // tabular figures keep it from jittering as the count ticks.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            text,
            style: theme.textTheme.labelMedium!.copyWith(
              color: colors.onPrimary,
              fontFeatures: kLiveNumberFontFeatures,
            ),
          ),
        ),
      ),
    );
  }
}
