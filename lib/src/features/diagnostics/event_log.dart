/// The "Moss events" diagnostics section.
///
/// `EventLog` -- a `DiagnosticsGroup` whose body is either a
/// `DiagnosticsEmptyState` ("No events yet" + description) or a
/// scrollable list of the last 40 events (newest first). Each event row
/// is a time span + a strong column (the event name + an optional detail
/// span). Reuses the shared primitives `DiagnosticsGroup` /
/// `DiagnosticsEmptyState` (from `diagnostics_sections.dart`) and the
/// pure helpers `formatTime` / `compactDetail` (from
/// `diagnostics_helpers.dart`).
///
/// `ChannelDiagnostics` / `GroupDiagnostics` sections are still deferred
/// (their contracts do not exist in the Flutter fork yet).
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The "Moss events" diagnostics group: the last 40 events, newest first
/// (an empty slice renders the empty-state). Each row is a time span
/// (left) + a strong column (event name + optional detail span). The
/// row's time is `formatTime(event.epoch_millis)` (local HH:mm:ss,
/// plain digits). The detail span is `compactDetail(event.detail_json)`
/// when non-empty, omitted when empty.
///
/// The group label ("Moss events"), the empty-state title ("No events
/// yet"), and the description are localized (ARB). The event NAME, the
/// formatted TIME, and the detail string are DATA (not localized). The
/// per-event-name color tint is applied to the event name only; time and
/// detail remain neutral.
class EventLog extends StatelessWidget {
  const EventLog({super.key, required this.events});

  /// The session's recent events, oldest first (the slice takes the last
  /// 40 and reverses to newest first).
  final List<SnapshotEvent> events;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final slice = events.length > 40
        ? events.sublist(events.length - 40).reversed.toList()
        : events.reversed.toList();
    return DiagnosticsGroup(
      label: l.diagGroupMossEvents,
      leading: const Icon(Icons.show_chart, size: 11),
      children: [
        if (slice.isEmpty)
          DiagnosticsEmptyState(
            title: l.diagNoEventsTitle,
            description: l.diagNoEventsBody,
          )
        else
          _EventScroll(slice: slice),
      ],
    );
  }
}

/// The scrollable list of event rows inside `EventLog`. A bounded
/// `ListView` is safe here because the drawer already constrains the
/// group's max height. Private to this file.
class _EventScroll extends StatelessWidget {
  const _EventScroll({required this.slice});

  /// The already-sliced, newest-first events to render.
  final List<SnapshotEvent> slice;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        for (final event in slice) _EventRow(event: event),
      ],
    );
  }
}

/// A single event row: a time span (left) + a strong column (event name
/// + optional detail span).
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final SnapshotEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final time = formatTime(event.epochMillis);
    final detail = compactDetail(event.detailJson);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The time span: left-aligned, mono, muted.
          Text(
            time,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: muted,
            ),
          ),
          const SizedBox(width: 10),
          // The event name (bold) + the optional detail span.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.eventName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: eventNameColor(
                      event.eventName,
                      fallback: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: muted,
                    ),
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
Color eventNameColor(String eventName, {required Color fallback}) {
  switch (eventName) {
    case 'peer_joined':
    case 'supernode_promoted':
      return MoshColors.moss;
    case 'peer_left':
      return MoshColors.warn;
    case 'tracker_announce':
      return MoshColors.info;
    case 'tracker_failure':
      return MoshColors.danger;
    default:
      return fallback;
  }
}
