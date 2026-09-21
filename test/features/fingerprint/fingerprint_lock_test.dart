// Widget tests for the header lock and the fingerprint dialog it
// opens: empty fingerprint renders no lock, a lock carries the E2EE
// tooltip, and tapping it opens the dialog with the emoji quartet,
// the hex, the hint, and a working Close button.
// See fingerprint-lock.plan.md step 4.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';
import '../../support/pump.dart';

void main() {
  const fingerprint = '0011223344556677';

  Widget lockWith(String fp) => Scaffold(
        body: FingerprintLock(fingerprint: fp, hint: 'same on both sides'),
      );

  testWidgets('empty fingerprint renders no lock', (tester) async {
    await pumpScreen(tester, lockWith(''));
    // The widget self-gates: it stays in the tree but renders nothing.
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(
      tester.getSize(find.byType(FingerprintLock)),
      Size.zero,
    );
  });

  testWidgets('lock renders with the E2EE tooltip', (tester) async {
    await pumpScreen(tester, lockWith(fingerprint));
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.byTooltip('End-to-end encrypted'), findsOneWidget);
  });

  testWidgets('tapping the lock opens the dialog with emoji, hex, hint',
      (tester) async {
    await pumpScreen(tester, lockWith(fingerprint));
    await tester.tap(find.byIcon(Icons.lock));
    await tester.pumpAndSettle();

    // Title, hex, hint, and the quartet (joined emoji string).
    expect(find.text('Encryption fingerprint'), findsOneWidget);
    expect(find.text(fingerprint), findsOneWidget);
    expect(find.text('same on both sides'), findsOneWidget);
    expect(
      find.text(fingerprintEmoji(fingerprint).join()),
      findsOneWidget,
    );
    // The dialog is closable.
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption fingerprint'), findsNothing);
  });
}
