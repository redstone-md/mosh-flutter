// The sender-name popover: tapping someone's name in a channel or a group
// offers to start a DM with them.
//
// Drives ConversationSenderMeta directly with a recording onMessage, so no
// Gateway is involved. Covers: who gets a tap target, when the Message
// button is disabled and what it says, and that tapping it reports the
// fingerprint and closes the popover.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/features/shared/toasts/toast_card.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';
import '../../support/pump.dart';

void main() {
  group('PeerNickname popover', () {
    const own = 'fp-me';
    const peerFp = 'fp-bob';

    testWidgets(
      'non-own name is tappable and opens a popover with a Message button',
      (tester) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: ConversationSenderMeta(
              fromDevice: 'bob',
              fromFingerprint: peerFp,
              sentAtMs: BigInt.from(1700000000000),
              peer: PeerActions(
                ownFingerprint: own,
                offered: const {},
                busy: false,
                onMessage: (_) async {},
              ),
            ),
          ),
        );

        // The name is wrapped in an InkWell tap target.
        expect(find.byType(InkWell), findsOneWidget);
        // The visible name renders.
        expect(find.text('bob'), findsOneWidget);
        // No popover yet.
        expect(find.byType(AlertDialog), findsNothing);

        // Tap the name to open the popover.
        await tester.tap(find.text('bob'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        // The Message button (en) renders + is enabled.
        final messageButton = find.text('Message');
        expect(messageButton, findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.ancestor(
                  of: messageButton,
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'Message button is DISABLED + labelled "Invite sent" when offered',
      (tester) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: ConversationSenderMeta(
              fromDevice: 'bob',
              fromFingerprint: peerFp,
              sentAtMs: BigInt.from(1700000000000),
              peer: PeerActions(
                ownFingerprint: own,
                offered: const {peerFp},
                busy: false,
                onMessage: (_) async {},
              ),
            ),
          ),
        );

        await tester.tap(find.text('bob'));
        await tester.pumpAndSettle();

        // Already offered -> label "Invite sent" (en).
        final inviteSent = find.text('Invite sent');
        expect(inviteSent, findsOneWidget);
        // Disabled when alreadyOffered or busy.
        expect(
          tester
              .widget<FilledButton>(
                find.ancestor(
                  of: inviteSent,
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('Message button is DISABLED when busy', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: ConversationSenderMeta(
            fromDevice: 'bob',
            fromFingerprint: peerFp,
            sentAtMs: BigInt.from(1700000000000),
            peer: PeerActions(
              ownFingerprint: own,
              offered: const {},
              busy: true,
              onMessage: (_) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();

      // Not offered -> label stays "Message", but disabled because busy.
      final messageButton = find.text('Message');
      expect(messageButton, findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: messageButton,
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'tapping Message when enabled calls onMessage(fingerprint) and closes the popover',
      (tester) async {
        final offered = <String>[];
        await pumpScreen(
          tester,
          Scaffold(
            body: ConversationSenderMeta(
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
            ),
          ),
        );

        await tester.tap(find.text('bob'));
        await tester.pumpAndSettle();

        // Tap the enabled Message button -> onMessage(peerFp) + popover closes.
        await tester.tap(find.text('Message'));
        await tester.pumpAndSettle();

        expect(offered, [peerFp]);
        // The popover Dialog closed after the tap.
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets('a failed Message shows an error after the popover closes',
        (tester) async {
      final pending = Completer<void>();
      await pumpScreen(
        tester,
        Scaffold(
          body: ConversationSenderMeta(
            fromDevice: 'bob',
            fromFingerprint: peerFp,
            sentAtMs: BigInt.from(1700000000000),
            peer: PeerActions(
              ownFingerprint: own,
              offered: const {},
              busy: false,
              onMessage: (_) => pending.future,
            ),
          ),
        ),
      );
      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      pending.completeError(const ConversationBridgeError(
        kind: ConversationBridgeErrorKind.unavailable,
        message: 'offer publication failed',
      ));
      await tester.pumpAndSettle();

      expect(
          find.text('Mosh could not reach the network. Try again in a moment.'),
          findsOneWidget);
      expect(tester.widget<ToastCard>(find.byType(ToastCard)).entry.kind,
          ToastKind.error);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'peer == null (DM-row default) renders plain bold Text with NO tap target',
      (tester) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: ConversationSenderMeta(
              fromDevice: 'bob',
              fromFingerprint: peerFp,
              sentAtMs: BigInt.from(1700000000000),
            ),
          ),
        );

        // The name renders as plain bold Text.
        expect(find.text('bob'), findsOneWidget);
        // No InkWell / GestureDetector tap target (the tap target is only for
        // non-own channel/group names; DM rows render plain bold).
        expect(find.byType(InkWell), findsNothing);
        expect(find.byType(GestureDetector), findsNothing);
      },
    );

    testWidgets(
      'own fingerprint renders plain bold Text with NO popover (peer != null)',
      (tester) async {
        await pumpScreen(
          tester,
          Scaffold(
            body: ConversationSenderMeta(
              fromDevice: 'me',
              fromFingerprint: own,
              sentAtMs: BigInt.from(1700000000000),
              peer: PeerActions(
                ownFingerprint: own,
                offered: const {},
                busy: false,
                onMessage: (_) async {},
              ),
            ),
          ),
        );

        // Own name renders as plain bold.
        expect(find.text('me'), findsOneWidget);
        // No tap target + no popover for the own name.
        expect(find.byType(InkWell), findsNothing);
        expect(find.byType(GestureDetector), findsNothing);
      },
    );
  });
}
