 /// The React `EventLog` section (the "Moss events" `.diagnostic-group`),
 /// 1-в-1 with React's `src/features/private-dm/DiagnosticsDrawerSections.tsx`.
 /// This is the THIRD `SessionDiagnostics` group (after Conversation
 /// details and Moss network), and the last group needed for full
 /// `SessionDiagnostics` parity with React.
 ///
 /// In scope (this atomic): `EventLog` -- a `DiagnosticsGroup` whose body
 /// is either a `DiagnosticsEmptyState` ("No events yet" + description)
 /// or a scrollable list of the last 40 events (newest first). Each event
 /// row is a time span + a strong column (the event name + an optional
 /// detail span). Reuses the shared primitives `DiagnosticsGroup` /
 /// `DiagnosticsEmptyState` (from `diagnostics_sections.dart`) and the
 /// pure helpers `formatTime` / `compactDetail` (from
 /// `diagnostics_helpers.dart`).
 ///
 /// DEFERRED: the per-event-name color tint (React's `event-${event_name}`
 /// CSS class keys rows by event type) is rendered neutral here -- the
 /// content + row shape are the parity surface; the decorative tint can
 /// be added later without changing the row content. The
 /// `ChannelDiagnostics` / `GroupDiagnostics` sections are still deferred
 /// (their contracts do not exist in the Flutter fork yet).
 library;
 
 import 'package:flutter/material.dart';
 
 import 'package:mosh/l10n/app_localizations.dart';
 import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
 import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
 import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
 
 /// The React `EventLog`: the "Moss events" `.diagnostic-group`. Mirrors
 /// React's `EventLog({ events })`:
 ///   - `slice = events.slice(-40).reverse()` -- the last 40 events,
 ///     newest first (an empty slice renders the empty-state).
 ///   - empty -> the "Moss events" label + a `DiagnosticsEmptyState`
 ///     ("No events yet" title + description).
 ///   - else -> the "Moss events" label + a scrollable list of rows, one
 ///     per event in the slice. Each row is a time span (left) + a strong
 ///     column (event name + optional detail span). The row's time is
 ///     `formatTime(event.epoch_millis)` (local HH:mm:ss, plain digits).
 ///     The detail span is `compactDetail(event.detail_json)` when it is
 ///     non-empty (omitted when empty, matching React's
 ///     `detail ? <span>{detail}</span> : null`).
 ///
 /// The group label ("Moss events"), the empty-state title ("No events
 /// yet"), and the description are localized (ARB). The event NAME, the
 /// formatted TIME, and the detail string are DATA (not localized). The
 /// per-event-name color tint (React's `event-${event_name}` CSS) is
 /// deferred -- rows render neutral here.
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
 
 /// The scrollable list of event rows inside `EventLog`. React wraps the
 /// rows in a `.diagnostic-scroll` container; the Flutter idiom is a
 /// `ListView` (the drawer already constrains the group's max height, so
 /// a bounded `ListView` is safe here). Private to this file.
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
 
 /// A single `event-row`: a time span (left) + a strong column (event name
 /// + optional detail span). Mirrors React's
 /// `.diagnostic-row.event-row.event-${event_name}`:
 ///   <div class="diagnostic-row event-row event-<name>">
 ///     <span>{time}</span>
 ///     <strong>
 ///       <span class="event-name">{event_name}</span>
 ///       {detail ? <span class="event-detail">{detail}</span> : null}
 ///     </strong>
 ///   </div>
 ///
 /// The per-event-name color tint (React's `event-${event_name}` CSS class)
 /// is DEFERRED -- rows render neutral here. A small map of per-name
 /// tints can be added later without changing the row content/shape.
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
           // React's <span>{time}</span> -- left-aligned, mono, fg-3.
           Text(
             time,
             style: TextStyle(
               fontFamily: 'monospace',
               fontSize: 10,
               color: muted,
             ),
           ),
           const SizedBox(width: 10),
           // React's <strong> -- the event name (bold) + the optional
           // detail span.
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
                     color: theme.colorScheme.onSurface,
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
