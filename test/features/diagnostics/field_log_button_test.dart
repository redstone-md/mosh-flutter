// The field log leaves the device only when the user shares it: one text
// file, oldest line first, reachable even when the launch failed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/diagnostics/field_log_button.dart';
import 'package:mosh/src/state/gateway_provider.dart';

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

  testWidgets('an empty log says so instead of sharing nothing',
      (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(body: FieldLogButton()),
      overrides: [bridgeFacadeProvider.overrideWithValue(ScriptableBridge())],
    );

    await tester.tap(find.text('Share app log'));
    await tester.pumpAndSettle();

    expect(find.text('The log is empty so far.'), findsOneWidget);
  });
}
