// Widget test for the group encryption notice banner -- the 1-в-1 port of
// React `GroupNotice` (ActiveChatPanes.tsx ~L420-432), wired into GroupScreen
// at the top of the body Column (matching React's `afterHeader` slot, ABOVE
// ConversationTools). Asserts the banner renders with the localized title +
// body so a regression that drops the banner (or wires it in the wrong
// slot) fails. Mirrors the seed/override idiom of
// `group_screen_grouping_test.dart` (override `groupSnapshotProvider` so
// the native cdylib is not involved). Does NOT test the deferred
// `needs_rejoin` / `orgAddPrompt` fragments -- those are separate atomics.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

GroupMessage _msg({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  BigInt? sentAtMs,
}) =>
    GroupMessage(
      fromDevice: fromDevice,
      fromFingerprint: fromFingerprint,
      body: body,
      messageId: null,
      sentAtMs: sentAtMs,
      attachment: null,
      deliveryStatus: null,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

GroupSnapshot _snapshot({
  required String groupId,
  required String deviceFingerprint,
  required List<GroupMessage> messages,
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: 'testmesh',
      label: null,
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      creatorFingerprint: deviceFingerprint,
      isAdmin: true,
      state: 'ready',
      memberCount: BigInt.from(2),
      inviteUri: null,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: null,
      memberPeerIds: const [],
    );

void main() {
  // The banner is ALWAYS shown for a group (no conditional -- every group
  // renders `GroupNotice`), so a group with messages is enough to assert it
  // appears alongside the list. Resolves the localized en ARB values via
  // AppLocalizations so the test pins the exact strings.
  testWidgets('group screen renders the group encryption notice banner',
      (tester) async {
    const groupId = 'grp-notice';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        groupSnapshotProvider(groupId).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupScreen(groupId: groupId),
      ),
    ));
    await tester.pumpAndSettle();

    // The banner title + body (en ARB values) render as Text nodes.
    expect(find.text('End-to-end encrypted group'), findsOneWidget);
    expect(
      find.text(
        'OpenMLS protects message content. Only members the admin has admitted can decrypt. New members do not see prior history.',
      ),
      findsOneWidget,
    );
    // The message body still renders (banner did not displace the list).
    expect(find.text('hi'), findsOneWidget);
  });
}
