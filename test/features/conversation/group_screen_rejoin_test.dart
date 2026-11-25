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
import '../../support/message_builders.dart';
import '../../support/pump.dart';

Future<void> _pump(WidgetTester tester, GroupSnapshot snapshot) =>
    pumpScreen(tester, GroupScreen(groupId: snapshot.groupId), overrides: [
      groupSnapshotProvider(snapshot.groupId)
          .overrideWith((ref) async => snapshot),
    ]);

void main() {
  const title = 'Group out of sync';
  const body =
      'The group is out of sync. Ask an administrator to invite you again.';
  testWidgets(
      'needsRejoin=true renders the rejoin-needed inline-error (title + body)',
      (tester) async {
    const groupId = 'grp-rejoin-true';
    final snapshot = TestSnapshots.group(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      needsRejoin: true,
      messages: [
        TestMessages.group(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pump(tester, snapshot);

    expect(find.text(title), findsOneWidget);
    expect(find.text(body), findsOneWidget);
    // The message body still renders (the banner did not displace the list).
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets(
      'needsRejoin=false does NOT render the rejoin-needed inline-error',
      (tester) async {
    const groupId = 'grp-rejoin-false';
    final snapshot = TestSnapshots.group(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      needsRejoin: false,
      messages: [
        TestMessages.group(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );
    await _pump(tester, snapshot);

    // The inline-error does not render at all when needsRejoin is false.
    expect(find.text(title), findsNothing);
    // The message body still renders.
    expect(find.text('hi'), findsOneWidget);
  });
}
