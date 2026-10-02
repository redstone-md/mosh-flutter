import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';

Future<void> _pumpHeader(WidgetTester tester) =>
    pumpScreen(tester, const DmScreen(sessionId: 'header'), overrides: [
      activeSessionProvider('header').overrideWith((ref) async =>
          TestSnapshots.dm(
              sessionId: 'header',
              peerDisplayName: 'Alice',
              fingerprint: '0011223344556677')),
    ]);

void main() {
  testWidgets('header actions follow call, search, menu with equal hit targets',
      (tester) async {
    await _pumpHeader(tester);
    final icons = [Icons.phone_outlined, Icons.search, Icons.more_vert];
    final centers =
        icons.map((icon) => tester.getCenter(find.byIcon(icon)).dx).toList();
    expect(centers[0], lessThan(centers[1]));
    expect(centers[1], lessThan(centers[2]));
    for (final icon in icons) {
      final target = find
          .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
          .first;
      expect(tester.getSize(target), const Size.square(40));
    }
  });

  testWidgets('clicking the chat name opens details', (tester) async {
    await _pumpHeader(tester);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byType(PeerStatusDrawer), findsOneWidget);
  });

  testWidgets('the identity opens details from the keyboard', (tester) async {
    await _pumpHeader(tester);
    Focus.of(tester.element(find.text('Alice'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PeerStatusDrawer), findsOneWidget);
  });

  testWidgets('the fingerprint remains a separate action within the identity',
      (tester) async {
    await _pumpHeader(tester);
    await tester.tap(find.byTooltip('End-to-end encrypted'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption fingerprint'), findsOneWidget);
    expect(find.byType(PeerStatusDrawer), findsNothing);
  });
}
