// The Conversation empty card (MOSH-138): what a conversation shows when it
// has nothing to show, and when it could not be loaded.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/conversation/conversation_notice.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'a conversation that failed to load says what is safe, hides the raw '
      'error and loads on Try again', (tester) async {
    var failing = true;
    await pumpScreen(tester, const DmScreen(sessionId: 'load'), overrides: [
      activeSessionProvider('load').overrideWith((ref) async {
        if (failing) throw StateError('sqlite: disk I/O error');
        return TestSnapshots.dm(sessionId: 'load', peerDisplayName: 'Alice');
      }),
    ]);
    final title = find.text('This conversation could not be loaded');
    expect(tester.widget<Text>(title).style!.color, MoshColors.dark.error);
    expect(find.text('Its messages are safe on this device'), findsOneWidget);
    expect(find.textContaining('sqlite'), findsNothing);

    failing = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(find.text('No messages yet.'), findsOneWidget);
  });

  testWidgets('an empty conversation offers no action', (tester) async {
    await pumpScreen(tester, const DmScreen(sessionId: 'empty'), overrides: [
      activeSessionProvider('empty').overrideWith((ref) async =>
          TestSnapshots.dm(sessionId: 'empty', peerDisplayName: 'Alice')),
    ]);
    final notice = find.byType(ConversationNotice);
    expect(notice, findsOneWidget);
    expect(find.descendant(of: notice, matching: find.byType(OutlinedButton)),
        findsNothing);
    expect(tester.widget<Text>(find.text('No messages yet.')).style!.color,
        MoshColors.dark.onSurface);
  });
}
