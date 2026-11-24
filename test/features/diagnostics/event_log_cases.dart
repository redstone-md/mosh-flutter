// Widget + pure tests for `EventLog`
import '../../support/pump.dart';
// (lib/src/features/diagnostics/event_log.dart) and the `formatTime` /
// `compactDetail` helpers (diagnostics_helpers.dart). Pumps the widget
// directly inside a localized `MaterialApp` (the established DM
// widget-test pattern, scoped to the section -- no Riverpod /
// DiagnosticsScreen) and asserts:
//   - `formatTime` pure: null -> "-", BigInt.zero -> "-", a local
//     wall-clock time -> its zero-padded HH:mm:ss.
//   - `compactDetail` pure: empty -> "", empty object -> "", single-key
//     object -> "foo=bar", multi-key object -> "a=1 b=2", nested-object
//     value -> 'k={"n":1}', top-level array -> "0=1 1=2" (array indexed
//     as-object), top-level number -> "42", top-level string -> "hi",
//     invalid JSON -> raw fallback.
//   - `EventLog` with empty events -> the "Moss events" group label +
//     the "No events yet" empty-state title + description.
//   - `EventLog` with 3 events (distinct names + epochMillis) -> 3 rows
//     rendered newest first, each with its time + name.
//   - `EventLog` with 45 events -> only the last 40 render (the slice).
//
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/event_log.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';

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

/// The epoch of a local wall-clock time, so the expected HH:mm:ss holds in
/// any host timezone.
BigInt _localEpoch(int hour, int minute, int second) => BigInt.from(
    DateTime(2026, 1, 15, hour, minute, second).millisecondsSinceEpoch);

Future<void> _pump(WidgetTester tester, Widget child) => pumpScreen(
    tester, Scaffold(body: SingleChildScrollView(child: Center(child: child))));

void main() {
  group('formatTime', () {
    test('null epoch -> "-"', () {
      expect(formatTime(null), '-');
    });

    test('BigInt.zero -> "-"', () {
      expect(formatTime(BigInt.zero), '-');
    });

    test('a local time -> HH:mm:ss, sub-10 fields zero-padded', () {
      expect(formatTime(_localEpoch(9, 5, 7)), '09:05:07');
      expect(formatTime(_localEpoch(23, 59, 58)), '23:59:58');
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
      // Dart jsonEncode emits 'k={"n":1}' with no spaces.
      expect(compactDetail('{"k":{"n":1}}'), 'k={"n":1}');
    });

    test('nested-array value -> k=JSON.stringify(value)', () {
      expect(compactDetail('{"k":[1,2]}'), 'k=[1,2]');
    });

    test('top-level array -> "0=1 1=2" (array-as-object indices)', () {
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

  group('eventNameColor', () {
    const fallback = Color(0xFF6B7075);

    test('maps all semantic event-name groups', () {
      expect(eventNameColor('peer_joined', MoshColors.dark, fallback: fallback),
          MoshColors.dark.primary);
      expect(
          eventNameColor('supernode_promoted', MoshColors.dark,
              fallback: fallback),
          MoshColors.dark.primary);
      expect(eventNameColor('peer_left', MoshColors.dark, fallback: fallback),
          MoshColors.dark.warning);
      expect(
          eventNameColor('tracker_announce', MoshColors.dark,
              fallback: fallback),
          MoshColors.dark.info);
      expect(
          eventNameColor('tracker_failure', MoshColors.dark,
              fallback: fallback),
          MoshColors.dark.error);
    });

    test('keeps unknown event names on the neutral fallback', () {
      expect(
          eventNameColor('tracker_update', MoshColors.dark, fallback: fallback),
          fallback);
    });
  });

  group('EventLog - empty', () {
    testWidgets('renders the Moss events group label + No-events empty-state',
        (tester) async {
      await _pump(tester, const EventLog(events: []));

      // Group label "Moss events" is uppercased in the widget.
      expect(find.text('Moss events'), findsOneWidget);
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
        epochMillis: _localEpoch(9, 5, 7),
      );
      final e2 = _event(
        eventName: 'tracker_update',
        detailJson: '',
        epochMillis: _localEpoch(12, 30, 45),
      );
      final e3 = _event(
        eventName: 'relay_changed',
        detailJson: '{"from":"a","to":"b"}',
        epochMillis: _localEpoch(23, 59, 58),
      );
      await _pump(tester, EventLog(events: [e1, e2, e3]));

      // Group label.
      expect(find.text('Moss events'), findsOneWidget);
      // Each event name renders exactly once.
      expect(find.text('peer_joined'), findsOneWidget);
      expect(find.text('tracker_update'), findsOneWidget);
      expect(find.text('relay_changed'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('relay_changed')).dy,
        lessThan(tester.getTopLeft(find.text('tracker_update')).dy),
      );
      expect(
        tester.getTopLeft(find.text('tracker_update')).dy,
        lessThan(tester.getTopLeft(find.text('peer_joined')).dy),
      );
      // Each event's local time renders exactly once.
      expect(find.text('09:05:07'), findsOneWidget);
      expect(find.text('12:30:45'), findsOneWidget);
      expect(find.text('23:59:58'), findsOneWidget);
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
