// CallLogEntry -- 1-в-1 port of React `src/features/private-dm/voice-call/
// CallLogEntry.tsx`. An inline pill rendered inside a DM message row when
// `ChatMessage.callEvent` is non-null (React MessageList L342:
// `{message.call_event ? <CallLogEntry event={message.call_event} : null}`).
//
// React renders a `span.call-log-entry` with a 14px phone icon + a label:
//   - kind === "missed" -> "Missed call" + IconPhoneOff, `call-log-missed`
//     class tints the text red (#e5484d).
//   - otherwise ("completed") -> "Call ended" + IconPhone, neutral tint.
// A non-zero `duration_ms` appends ` - m:ss` (e.g. "Call ended - 1:05");
// zero duration omits the suffix.
//
// Flutter port: an inline `Container` pill (React `.call-log-entry`:
// `padding: 4px 8px; border-radius: 8px; background:
// rgba(127,127,127,0.15); font-size: 12px`) wrapping a `Row` of the icon +
// label. Material `Icons.phone` / `Icons.phone_disabled` are the closest
// filled glyphs to tabler's `IconPhone` / `IconPhoneOff`. The missed tint
// uses React's `#e5484d` -> `Color(0xFFE5484D)`; completed stays the
// on-surface color. `formatCallDuration` mirrors React's `formatDuration`
// (returns "" for 0; otherwise `m:ss` with zero-padded seconds).

library;

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The React `.call-log-entry` kind literal for a missed call.
const String callEventKindMissed = 'missed';

/// Formats a duration in milliseconds as `m:ss` (zero-padded seconds),
/// or an empty string when the duration is zero -- mirroring React's
/// `formatDuration` in CallLogEntry.tsx.
String formatCallDuration(BigInt durationMs) {
  final total = (durationMs <= BigInt.zero)
      ? 0
      : (durationMs ~/ BigInt.from(1000)).toInt();
  if (total == 0) return '';
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// An inline call-event pill -- 1-в-1 with React's `CallLogEntry`.
///
/// Renders inside a DM message row when [event] is non-null. The pill's
/// background is React's `rgba(127, 127, 127, 0.15)` (a neutral 15% tint);
/// the missed variant tints the icon + text with React's `#e5484d`.
class CallLogEntry extends StatelessWidget {
  const CallLogEntry({
    super.key,
    required this.event,
    required this.l,
  });

  /// The call event to render (React `event: CallEvent`).
  final CallEvent event;

  /// Localizations (callLogMissedLabel / callLogEndedLabel).
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missed = event.kind == callEventKindMissed;
    final duration = formatCallDuration(event.durationMs);
    // React `.call-log-missed` -> `color: #e5484d`. Completed stays the
    // default on-surface text color.
    final accent =
        missed ? const Color(0xFFE5484D) : theme.colorScheme.onSurface;
    // React `.call-log-entry` background `rgba(127, 127, 127, 0.15)`.
    final pillBg = const Color(0xFF7F7F7F).withValues(alpha: 0.15);
    final label = missed ? l.callLogMissedLabel : l.callLogEndedLabel;
    final text = duration.isEmpty ? label : '$label - $duration';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            // React tabler IconPhoneOff (missed) / IconPhone (completed).
            // Material's filled phone glyphs are the closest equivalents.
            missed ? Icons.phone_disabled : Icons.phone,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: accent,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
