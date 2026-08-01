/// Shared DM / message-row helpers extracted from `dm_screen.dart` and
/// `sessions_screen.dart` to keep feature screens under the 500-line
/// file-size discipline (ADR: file-size discipline). These are pure,
/// dependency-light utilities used by the DM message row and the
/// sessions list row -- previously duplicated as private helpers in each
/// screen. They are intentionally public so the screens can import the
/// shared copy and drop their local duplicates.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/rust/outbound_delivery.dart';

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
