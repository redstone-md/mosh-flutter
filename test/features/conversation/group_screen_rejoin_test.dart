// Widget test for the group `needs_rejoin` inline-error, wired into
// GroupScreen between the CryptoNoticeBanner (GroupNotice) and
// ConversationTools. Asserts the inline-error renders with the localized
// title (with the appended period) + body when `needsRejoin` is true, and
// does NOT render when false. Mirrors the seed/override idiom of
// `group_screen_notice_test.dart` (override `groupSnapshotProvider` so the
// native cdylib is not involved). Does NOT test the deferred
// `orgAddPrompt` fragment (separate atomic).
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import '../../support/pump.dart';

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
  required bool needsRejoin,
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
      needsRejoin: needsRejoin,
      orgPubkey: null,
      memberPeerIds: const [],
      typingMembers: const [],
    );

Future<void> _pump(WidgetTester tester, GroupSnapshot snapshot) =>
    pumpScreen(tester, GroupScreen(groupId: snapshot.groupId), overrides: [
      groupSnapshotProvider(snapshot.groupId)
          .overrideWith((ref) async => snapshot),
    ]);

void main() {
  // The title ARB value ("Group out of sync") has NO trailing period; the
  // widget appends it. The title + "." + " " + body render as a single
  // `Text.rich`, so its `toPlainText()` is the concatenation "Group out of
  // sync. This group missed...". `find.text` matches a `Text.rich` by its
  // span's `toPlainText()`, so we assert on the full string (the bold span
  // carries the appended period).
  const expectedInlineError =
      'Group out of sync. This group missed membership changes that could '
      'not be replayed. Ask an admin to re-invite you from the roster.';
  testWidgets(
      'needsRejoin=true renders the rejoin-needed inline-error (title + body)',
      (tester) async {
    const groupId = 'grp-rejoin-true';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      needsRejoin: true,
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pump(tester, snapshot);

    // The whole inline-error renders as one `Text.rich`; its plain text is
    // the bold title (with appended period) + space + body.
    expect(find.text(expectedInlineError), findsOneWidget);
    // The message body still renders (the banner did not displace the list).
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets(
      'needsRejoin=false does NOT render the rejoin-needed inline-error',
      (tester) async {
    const groupId = 'grp-rejoin-false';
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      needsRejoin: false,
      messages: [
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pump(tester, snapshot);

    // The inline-error does not render at all when needsRejoin is false.
    expect(find.text(expectedInlineError), findsNothing);
    // The message body still renders.
    expect(find.text('hi'), findsOneWidget);
  });
}
