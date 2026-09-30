import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/async_switch_tile.dart';

import '../../support/pump.dart';

void main() {
  testWidgets('a tap during a pending write is ignored', (tester) async {
    final pending = Completer<void>();
    final writes = <bool>[];
    await pumpScreen(
      tester,
      Scaffold(
        body: AsyncSwitchTile(
          title: 't',
          subtitle: 's',
          read: () async => false,
          write: (value) {
            writes.add(value);
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(writes, [true],
        reason: 'overlapping writes can finish out of order');

    pending.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(writes, [true, false], reason: 'the switch re-enables once done');
  });
}
