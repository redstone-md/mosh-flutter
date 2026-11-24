import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;

/// The "Moss events" group of connection status: the last 40 events, newest
/// first, or its empty state. The event's name, time and detail are data,
/// not localized; the name alone takes the colour of what happened.
class EventLog extends StatelessWidget {
  const EventLog({super.key, required this.events});

  /// The session's recent events, oldest first.
  final List<SnapshotEvent> events;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final slice = events.length > 40
        ? events.sublist(events.length - 40).reversed
        : events.reversed;
    return DiagnosticsGroup(
      label: l.diagGroupMossEvents,
      children: [
        if (slice.isEmpty)
          DiagnosticsEmptyState(
            title: l.diagNoEventsTitle,
            description: l.diagNoEventsBody,
          ),
        for (final event in slice) _EventRow(event: event),
      ],
    );
  }
}

/// The Event row card: when it happened, what happened, and its detail.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final SnapshotEvent event;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    final detail = compactDetail(event.detailJson);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MoshSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatTime(event.epochMillis),
              style: text.labelSmall!
                  .copyWith(fontFeatures: kLiveNumberFontFeatures)),
          const SizedBox(width: MoshSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.eventName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium!.copyWith(
                        color: eventNameColor(event.eventName, colors,
                            fallback: colors.onSurface))),
                if (detail.isNotEmpty)
                  Tooltip(
                    message: detail,
                    child: Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps event names to semantic colors, preserving the supplied neutral
/// fallback for event types without an explicit mapping.
Color eventNameColor(String eventName, MoshColors colors,
    {required Color fallback}) {
  switch (eventName) {
    case 'peer_joined':
    case 'supernode_promoted':
      return colors.primary;
    case 'peer_left':
      return colors.warning;
    case 'tracker_announce':
      return colors.info;
    case 'tracker_failure':
      return colors.error;
    default:
      return fallback;
  }
}
