import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The event kind literal for a missed call.
const String callEventKindMissed = 'missed';

/// Formats a duration in milliseconds as `m:ss` (zero-padded seconds),
/// or an empty string when the duration is zero.
String formatCallDuration(BigInt durationMs) {
  final total = (durationMs <= BigInt.zero)
      ? 0
      : (durationMs ~/ BigInt.from(1000)).toInt();
  if (total == 0) return '';
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// An inline call-event pill.
///
/// Renders inside a DM message row when [event] is non-null. The pill's
/// background is a neutral 15% gray tint; the missed variant tints the
/// icon + text with #e5484d.
class CallLogEntry extends StatelessWidget {
  const CallLogEntry({
    super.key,
    required this.event,
    required this.l,
  });

  /// The call event to render.
  final CallEvent event;

  /// Localizations (callLogMissedLabel / callLogEndedLabel).
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missed = event.kind == callEventKindMissed;
    final duration = formatCallDuration(event.durationMs);
    // Missed calls tint red; completed stays the on-surface text color.
    final accent =
        missed ? const Color(0xFFE5484D) : theme.colorScheme.onSurface;
    // 15% gray pill background.
    final pillBg = const Color(0xFF7F7F7F).withValues(alpha: 0.15);
    final label = missed ? l.callLogMissedLabel : l.callLogEndedLabel;
    // U+00B7 MIDDLE DOT with a space on each side separates the duration.
    final text = duration.isEmpty ? label : '$label \u00B7 $duration';
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
            // Phone-off glyph for a missed call, phone for completed.
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
