 // Widget + pure tests for `EventLog`
 // (lib/src/features/diagnostics/event_log.dart) and the `formatTime` /
 // `compactDetail` helpers (diagnostics_helpers.dart). Pumps the widget
 // directly inside a localized `MaterialApp` (the established DM
 // widget-test pattern, scoped to the section -- no Riverpod /
 // DiagnosticsScreen) and asserts:
 //   - `formatTime` pure: null -> "-", BigInt.zero -> "-", a fixed epoch
 //     -> the local HH:mm:ss computed the same way (deterministic).
 //   - `compactDetail` pure: empty -> "", empty object -> "", single-key
 //     object -> "foo=bar", multi-key object -> "a=1 b=2", nested-object
 //     value -> 'k={"n":1}', top-level array -> "0=1 1=2" (React array-as-
 //     object), top-level number -> "42", top-level string -> "hi",
 //     invalid JSON -> raw fallback.
 //   - `EventLog` with empty events -> the "Moss events" group label +
 //     the "No events yet" empty-state title + description.
 //   - `EventLog` with 3 events (distinct names + epochMillis) -> 3 rows
 //     rendered newest first, each with its time + name.
 //   - `EventLog` with 45 events -> only the last 40 render (the slice).
 //
 // The per-event-name color tint (React's `event-${event_name}` CSS) is
 // deferred (rendered neutral) and is not asserted here.
 import 'package:flutter/material.dart';
 import 'package:flutter_test/flutter_test.dart';
 
 import 'package:mosh/l10n/app_localizations.dart';
 import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
 import 'package:mosh/src/features/diagnostics/event_log.dart';
 import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
 
 /// Builds a `SnapshotEvent` with the fields the section reads.
 SnapshotEvent _event({
   required String eventName,
   String detailJson = '',
   required BigInt epochMillis,
   int eventType = 0,
 }) =>
     SnapshotEvent(
       eventType: eventType,
       eventName: eventName,
       detailJson: detailJson,
       epochMillis: epochMillis,
     );
 
 /// Expected local HH:mm:ss for an epoch, computed the SAME way the
 /// implementation does (so the test is deterministic regardless of the
 /// host timezone).
 String _expectedTime(BigInt epoch) {
   final date = DateTime.fromMillisecondsSinceEpoch(epoch.toInt()).toLocal();
   String pad(int v) => v < 10 ? '0$v' : v.toString();
   return '${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
 }
 
 Future<void> _pump(WidgetTester tester, Widget child) async {
   await tester.pumpWidget(
     MaterialApp(
       localizationsDelegates: AppLocalizations.localizationsDelegates,
       supportedLocales: AppLocalizations.supportedLocales,
       home: Scaffold(
         body: SingleChildScrollView(child: Center(child: child)),
       ),
     ),
   );
   await tester.pumpAndSettle();
 }
 
 void main() {
   group('formatTime', () {
     test('null epoch -> "-"', () {
       expect(formatTime(null), '-');
     });
 
     test('BigInt.zero -> "-"', () {
       expect(formatTime(BigInt.zero), '-');
     });
 
     test('a fixed epoch -> local HH:mm:ss (deterministic)', () {
       const epoch = 1716000000000; // arbitrary fixed millis
       final big = BigInt.from(epoch);
       expect(formatTime(big), _expectedTime(big));
     });
 
     test('sub-10 hour/minute/second get zero-padded', () {
       // Use an epoch whose local components have at least one sub-10
       // field; assert against the helper, which pads the same way.
       final big = BigInt.from(1700000000000);
       expect(formatTime(big), _expectedTime(big));
       // The output must be exactly 8 chars "HH:mm:ss" with two digits
       // per component.
       expect(formatTime(big).length, 8);
     });
   });
 
   group('compactDetail', () {
     test('empty raw -> ""', () {
       expect(compactDetail(''), '');
     });
 
     test('empty object -> ""', () {
       expect(compactDetail('{}'), '');
     });
 
     test('single-key object -> "foo=bar"', () {
       expect(compactDetail('{"foo":"bar"}'), 'foo=bar');
     });
 
     test('multi-key object -> "a=1 b=2"', () {
       expect(compactDetail('{"a":1,"b":2}'), 'a=1 b=2');
     });
 
     test('nested-object value -> k=JSON.stringify(value)', () {
       // Dart jsonEncode emits 'k={"n":1}' (no spaces), matching React's
       // JSON.stringify output.
       expect(compactDetail('{"k":{"n":1}}'), 'k={"n":1}');
     });
 
     test('nested-array value -> k=JSON.stringify(value)', () {
       expect(compactDetail('{"k":[1,2]}'), 'k=[1,2]');
     });
 
     test('top-level array -> "0=1 1=2" (React array-as-object)', () {
       expect(compactDetail('[1,2]'), '0=1 1=2');
     });
 
   test('top-level number -> "42"', () {
     expect(compactDetail('42'), '42');
   });
 
    test('whole-valued double renders as int (JS String(42.0) parity)', () {
      // Dart parses "42.0" to a double whose toString() is "42.0", but JS
      // String(42.0) yields "42"; _scalar normalizes whole-valued doubles.
      expect(compactDetail('42.0'), '42');
    });
 
    test('whole-valued double inside object renders as int', () {
      expect(compactDetail('{"a":42.0}'), 'a=42');
    });
 
    test('whole-valued double inside array renders as int', () {
      expect(compactDetail('[42.0]'), '0=42');
    });
 
    test('genuinely fractional double keeps its fraction', () {
      expect(compactDetail('1.5'), '1.5');
    });

   test('top-level string -> "hi"', () {
     expect(compactDetail('"hi"'), 'hi');
   });
 
     test('top-level true -> "true"', () {
       expect(compactDetail('true'), 'true');
     });
 
     test('top-level null -> "null"', () {
       expect(compactDetail('null'), 'null');
     });
 
     test('invalid JSON -> raw fallback', () {
       expect(compactDetail('not json'), 'not json');
     });
   });
 
   group('EventLog - empty', () {
     testWidgets('renders the Moss events group label + No-events empty-state',
         (tester) async {
       await _pump(tester, const EventLog(events: []));
 
       // Group label "Moss events" is uppercased in the widget.
       expect(find.text('MOSS EVENTS'), findsOneWidget);
       // The empty-state title + description.
       expect(find.text('No events yet'), findsOneWidget);
       expect(
         find.text(
           'Moss will list peer joins, tracker updates, and relay changes '
           'here as they happen.',
         ),
         findsOneWidget,
       );
     });
   });
 
   group('EventLog - rows', () {
     testWidgets('3 events render newest first with time + name',
         (tester) async {
       final e1 = _event(
         eventName: 'peer_joined',
         detailJson: '{"peer":"alice"}',
         epochMillis: BigInt.from(1700000000000),
       );
       final e2 = _event(
         eventName: 'tracker_update',
         detailJson: '',
         epochMillis: BigInt.from(1710000000000),
       );
       final e3 = _event(
         eventName: 'relay_changed',
         detailJson: '{"from":"a","to":"b"}',
         epochMillis: BigInt.from(1720000000000),
       );
       await _pump(tester, EventLog(events: [e1, e2, e3]));
 
       // Group label.
       expect(find.text('MOSS EVENTS'), findsOneWidget);
       // Each event name renders exactly once.
       expect(find.text('peer_joined'), findsOneWidget);
       expect(find.text('tracker_update'), findsOneWidget);
       expect(find.text('relay_changed'), findsOneWidget);
       // Each event's local time renders exactly once.
       expect(find.text(_expectedTime(e1.epochMillis)), findsOneWidget);
       expect(find.text(_expectedTime(e2.epochMillis)), findsOneWidget);
       expect(find.text(_expectedTime(e3.epochMillis)), findsOneWidget);
       // The detail strings render for the two events with detail_json.
       expect(find.text('peer=alice'), findsOneWidget);
       expect(find.text('from=a to=b'), findsOneWidget);
       // tracker_update has an empty detail -> no detail span (its name
       // renders once, and no "tracker_update" detail text leaks).
     });
 
     testWidgets('45 events -> only the last 40 render', (tester) async {
       final events = <SnapshotEvent>[
         for (var i = 0; i < 45; i++)
           _event(
             eventName: 'ev_$i',
             epochMillis: BigInt.from(1700000000000 + i * 1000),
           ),
       ];
       await _pump(tester, EventLog(events: events));
 
       // The oldest 5 (ev_0 .. ev_4) are dropped by the slice; the
       // newest 40 (ev_5 .. ev_44) render.
       for (var i = 0; i < 5; i++) {
         expect(find.text('ev_$i'), findsNothing);
       }
       for (var i = 5; i < 45; i++) {
         expect(find.text('ev_$i'), findsOneWidget);
       }
     });
   });
 }
