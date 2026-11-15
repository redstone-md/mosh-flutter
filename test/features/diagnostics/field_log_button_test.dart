// The field log leaves the device only when the user shares it: one text
// file, oldest line first, reachable even when the launch failed.
import 'dart:async' show Completer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/diagnostics/field_log_button.dart';

import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

void main() {
  test('the export joins the rotated files oldest first', () async {
    final dir = await Directory.systemTemp.createTemp('mosh-field-log-');
    addTearDown(() => dir.delete(recursive: true));
    Future<String> file(String name, String text) async =>
        (await File('${dir.path}/$name').writeAsString(text)).path;
    final bridge = ScriptableBridge()
      ..seedLogFiles([
        await file('mosh.log', 'third\n'),
        await file('mosh.log.1', 'second\n'),
        await file('mosh.log.2', 'first\n'),
      ]);

    final export = await exportFieldLog(bridge, dir);

    expect(await export!.readAsString(), 'first\nsecond\nthird\n');
  });

  // The export's file work is covered above; here it is a fixed answer.
  Future<void> pumpButton(WidgetTester tester,
          {String? export = '/tmp/mosh-log.txt', FieldLogSend? send}) =>
      pumpScreen(
        tester,
        const Scaffold(body: FieldLogButton()),
        overrides: [
          fieldLogExportProvider.overrideWithValue(() async => export),
          fieldLogSendProvider.overrideWithValue(
              send ?? (_, __) async => fail('nothing to send')),
        ],
      );

  testWidgets('sharing hands over the exported file', (tester) async {
    final sent = <String>[];
    await pumpButton(tester, send: (path, _) async => sent.add(path));

    await tester.tap(find.text('Share app log'));
    await tester.pumpAndSettle();

    expect(sent, ['/tmp/mosh-log.txt']);
    expect(find.text('Could not share the log.'), findsNothing);
  });

  testWidgets('a second tap waits for the first share', (tester) async {
    final exporting = Completer<String?>();
    var exports = 0;
    await pumpScreen(
      tester,
      const Scaffold(body: FieldLogButton()),
      overrides: [
        fieldLogExportProvider.overrideWithValue(() {
          exports++;
          return exporting.future;
        }),
        fieldLogSendProvider.overrideWithValue((_, __) async {}),
      ],
    );

    await tester.tap(find.text('Share app log'));
    await tester.pump();
    await tester.tap(find.text('Share app log'));
    exporting.complete('/tmp/mosh-log.txt');
    await tester.pumpAndSettle();

    expect(exports, 1);
  });

  testWidgets('a share that fails says so', (tester) async {
    await pumpButton(tester,
        send: (_, __) async => throw StateError('no share sheet'));

    await tester.tap(find.text('Share app log'));
    await tester.pumpAndSettle();

    expect(find.text('Could not share the log.'), findsOneWidget);
  });

  testWidgets('an empty log says so instead of sharing nothing',
      (tester) async {
    await pumpButton(tester, export: null);

    await tester.tap(find.text('Share app log'));
    await tester.pumpAndSettle();

    expect(find.text('The log is empty so far.'), findsOneWidget);
  });
}
