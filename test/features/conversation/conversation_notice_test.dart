// The Conversation empty card (MOSH-138): a conversation that could not be
// loaded.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'a conversation that failed to load says so in the error colour and '
      'loads on Try again', (tester) async {
    var failing = true;
    await pumpScreen(tester, const DmScreen(sessionId: 'load'), overrides: [
      activeSessionProvider('load').overrideWith((ref) async {
        if (failing) throw StateError('sqlite: disk I/O error');
        return TestSnapshots.dm(sessionId: 'load', peerDisplayName: 'Alice');
      }),
    ]);
    final title = find.text('This conversation could not be loaded');
    expect(tester.widget<Text>(title).style!.color, MoshColors.dark.error);

    failing = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(find.text('No messages yet.'), findsOneWidget);
  });
}
