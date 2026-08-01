// Unit + widget tests for the OpenMLS-protection badge (`MlsBadge`) and
// its placement in the DM sender-meta row. `MlsBadge` lives in
// lib/src/features/dm/dm_helpers.dart (1-в-1 with React's `MlsBadge` in
// src/features/private-dm/MessageLists.tsx) and is composed into the
// sender meta via `SenderMeta` (extracted from dm_screen.dart to keep
// that screen under the 500-line file-size discipline).
//
// Coverage:
//   1. `MlsBadge` renders the literal acronym "MLS" (not localized).
//   2. `MlsBadge` exposes a `Tooltip` with the `mlsBadgeTooltip` message
//      and a `Semantics` label matching `mlsBadgeLabel`.
//   3. Pumped inside `DmScreen` with one non-grouped peer message, the
//      "MLS" badge renders next to the sender name (both visible).
//   4. Pumped with two peer messages from the same sender 1 minute apart
//      (the second groups under the first), "MLS" renders EXACTLY ONCE --
//      pinning the "badge only on non-grouped rows" behavior (the grouped
//      row omits the whole meta, so its badge is absent, matching React).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/session_providers.dart';

ChatMessage _msg({
  required String fromDevice,
  required String body,
  BigInt? sentAtMs,
}) =>
    ChatMessage(
      fromDevice: fromDevice,
      body: body,
      messageId: null,
      sentAtMs: sentAtMs,
      attachment: null,
      callEvent: null,
      deliveryStatus: null,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

SessionSnapshot _snapshot({
  required String sessionId,
  required String displayName,
  required List<ChatMessage> messages,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: '',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: '0123456789abcdef',
      messages: messages,
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

Widget _localized(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('MlsBadge', () {
    testWidgets('renders the literal "MLS" acronym', (tester) async {
      await tester.pumpWidget(_localized(const Scaffold(body: MlsBadge())));
      await tester.pumpAndSettle();
      expect(find.text('MLS'), findsOneWidget);
    });

    testWidgets('exposes the localized tooltip + semantics label', (tester) async {
      await tester.pumpWidget(_localized(const Scaffold(body: MlsBadge())));
      await tester.pumpAndSettle();

      final l = AppLocalizations.of(tester.element(find.text('MLS')))!;

      // Tooltip mirrors React's `title` on the `<code className="message-protocol">`.
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, l.mlsBadgeTooltip);

      // Semantics label mirrors React's `aria-label="OpenMLS protected"`.
      expect(find.bySemanticsLabel(l.mlsBadgeLabel), findsOneWidget);
    });
  });

  group('DmScreen sender-meta MLS badge', () {
    const sessionId = 'sess-1';
    final base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z

    testWidgets('renders next to the sender name on a non-grouped row',
        (tester) async {
      final snapshot = _snapshot(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          _msg(fromDevice: 'bob', body: 'first', sentAtMs: base),
        ],
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeSessionProvider(sessionId)
              .overrideWith((ref) async => snapshot),
        ],
        child: _localized(const DmScreen(sessionId: sessionId)),
      ));
      await tester.pumpAndSettle();

      // The sender name renders (so the badge sits next to it, not alone).
      expect(find.text('bob'), findsOneWidget);
      // The MLS badge renders in the meta row.
      expect(find.text('MLS'), findsOneWidget);
    });

    testWidgets(
        'renders EXACTLY ONCE when the second message groups under the first',
        (tester) async {
      final snapshot = _snapshot(
        sessionId: sessionId,
        displayName: 'alice',
        messages: [
          _msg(fromDevice: 'bob', body: 'first', sentAtMs: base),
          _msg(
              fromDevice: 'bob',
              body: 'second',
              sentAtMs: base + BigInt.from(60 * 1000)),
        ],
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeSessionProvider(sessionId)
              .overrideWith((ref) async => snapshot),
        ],
        child: _localized(const DmScreen(sessionId: sessionId)),
      ));
      await tester.pumpAndSettle();

      // Both message bodies render.
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);

      // The sender name renders exactly once (grouped row omits the meta).
      expect(find.text('bob'), findsOneWidget);

      // The MLS badge renders EXACTLY ONCE: the grouped row omits the whole
      // meta (so its badge is absent), matching React's DmMessageRow.
      expect(find.text('MLS'), findsOneWidget);
    });
  });
}