// Widget tests for the PeerNickname peer-actions popover (React
// `PeerNickname`, src/features/private-dm/MessageLists.tsx:198-244) and the
// `PeerActions` value object backing it (React `PeerActions` type,
// MessageLists.tsx:31-35). Both live in `lib/src/features/conversation/conversation_helpers.dart`
// (co-located with `MultiPartySenderMeta`, the only consumer). The tests
// pump `MultiPartySenderMeta` directly inside a localized `MaterialApp`
// (the meta is a pure `StatelessWidget` -- no providers, no async) with an
// injected `PeerActions.onMessage` recording callback, so the real Gateway
// is never touched (the popover's `onMessage` is an injected seam).
//
// Coverage:
//   1. peer != null + non-own fingerprint -> the name is wrapped in an
//      InkWell (tappable); tapping opens the popover Dialog with the
//      "Message" button.
//   2. "Message" is DISABLED (label "Invite sent") when the peer is in
//      `offered`.
//   3. "Message" is DISABLED when `busy == true` (label "Message").
//   4. "Message" is ENABLED when not offered and not busy; tapping it
//      calls `onMessage(fingerprint)` (recording callback) and closes the
//      popover.
//   5. peer == null (DM-row + existing-tests case) -> the name is plain
//      bold Text with NO InkWell/GestureDetector tap target.
//   6. peer != null + own fingerprint -> plain bold Text, no popover.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

Widget _localized(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('PeerNickname popover', () {
    const own = 'fp-me';
    const peerFp = 'fp-bob';

    testWidgets(
        'non-own name is tappable and opens a popover with a Message button',
        (tester) async {
      await tester.pumpWidget(_localized(MultiPartySenderMeta(
        fromDevice: 'bob',
        fromFingerprint: peerFp,
        sentAtMs: BigInt.from(1700000000000),
        peer: PeerActions(
          ownFingerprint: own,
          offered: const {},
          busy: false,
          onMessage: (_) async {},
        ),
      )));
      await tester.pumpAndSettle();

      // The name is wrapped in an InkWell tap target (React nick-button).
      expect(find.byType(InkWell), findsOneWidget);
      // The visible name renders.
      expect(find.text('bob'), findsOneWidget);
      // No popover yet.
      expect(find.byType(AlertDialog), findsNothing);

      // Tap the name to open the popover (React nick-popover, role=dialog).
      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // The Message button (en) renders + is enabled.
      final messageButton = find.text('Message');
      expect(messageButton, findsOneWidget);
      expect(
          tester.widget<TextButton>(find.ancestor(
            of: messageButton,
            matching: find.byType(TextButton),
          )).onPressed,
          isNotNull);
    });

    testWidgets(
        'Message button is DISABLED + labelled "Invite sent" when offered',
        (tester) async {
      await tester.pumpWidget(_localized(MultiPartySenderMeta(
        fromDevice: 'bob',
        fromFingerprint: peerFp,
        sentAtMs: BigInt.from(1700000000000),
        peer: PeerActions(
          ownFingerprint: own,
          offered: const {peerFp},
          busy: false,
          onMessage: (_) async {},
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();

      // Already offered -> label "Invite sent" (en).
      final inviteSent = find.text('Invite sent');
      expect(inviteSent, findsOneWidget);
      // Disabled when alreadyOffered (React disabled={alreadyOffered || busy}).
      expect(
          tester.widget<TextButton>(find.ancestor(
            of: inviteSent,
            matching: find.byType(TextButton),
          )).onPressed,
          isNull);
    });

    testWidgets('Message button is DISABLED when busy', (tester) async {
      await tester.pumpWidget(_localized(MultiPartySenderMeta(
        fromDevice: 'bob',
        fromFingerprint: peerFp,
        sentAtMs: BigInt.from(1700000000000),
        peer: PeerActions(
          ownFingerprint: own,
          offered: const {},
          busy: true,
          onMessage: (_) async {},
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();

      // Not offered -> label stays "Message", but disabled because busy.
      final messageButton = find.text('Message');
      expect(messageButton, findsOneWidget);
      expect(
          tester.widget<TextButton>(find.ancestor(
            of: messageButton,
            matching: find.byType(TextButton),
          )).onPressed,
          isNull);
    });

    testWidgets(
        'tapping Message when enabled calls onMessage(fingerprint) and closes the popover',
        (tester) async {
      final offered = <String>[];
      await tester.pumpWidget(_localized(MultiPartySenderMeta(
        fromDevice: 'bob',
        fromFingerprint: peerFp,
        sentAtMs: BigInt.from(1700000000000),
        peer: PeerActions(
          ownFingerprint: own,
          offered: const {},
          busy: false,
          onMessage: (fingerprint) async {
            offered.add(fingerprint);
          },
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();

      // Tap the enabled Message button -> onMessage(peerFp) + popover closes.
      await tester.tap(find.text('Message'));
      await tester.pumpAndSettle();

      expect(offered, [peerFp]);
      // The popover Dialog closed after the tap.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
        'peer == null (DM-row default) renders plain bold Text with NO tap target',
        (tester) async {
      await tester.pumpWidget(_localized(MultiPartySenderMeta(
        fromDevice: 'bob',
        fromFingerprint: peerFp,
        sentAtMs: BigInt.from(1700000000000),
      )));
      await tester.pumpAndSettle();

      // The name renders as plain bold Text.
      expect(find.text('bob'), findsOneWidget);
      // No InkWell / GestureDetector tap target (React PeerNickname is only
      // for non-own channel/group names; DM rows render plain bold).
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets(
        'own fingerprint renders plain bold Text with NO popover (peer != null)',
        (tester) async {
      await tester.pumpWidget(_localized(MultiPartySenderMeta(
        fromDevice: 'me',
        fromFingerprint: own,
        sentAtMs: BigInt.from(1700000000000),
        peer: PeerActions(
          ownFingerprint: own,
          offered: const {},
          busy: false,
          onMessage: (_) async {},
        ),
      )));
      await tester.pumpAndSettle();

      // Own name renders as plain bold (React <strong>{name}</strong>).
      expect(find.text('me'), findsOneWidget);
      // No tap target + no popover for the own name.
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}
