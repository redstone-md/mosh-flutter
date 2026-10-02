// Widget test for the group encryption notice banner wired into GroupScreen
// at the top of the body Column, above ConversationTools. Asserts the
// banner renders with the localized title + body so a regression that
// drops the banner (or wires it in the wrong slot) fails. Overrides
// `groupSnapshotProvider` so the native cdylib is not involved. Does NOT
// test the deferred `needs_rejoin` / `orgAddPrompt` fragments -- those are
// separate atomics.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';

void main() {
  // A group with messages on a fresh installation shows the notice
  // alongside the list. The assertions pin its English copy.
  testWidgets('group screen renders the group encryption notice banner',
      (tester) async {
    const groupId = 'grp-notice';
    final snapshot = TestSnapshots.group(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      messages: [
        TestMessages.group(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );

    await pumpScreen(tester, const GroupScreen(groupId: groupId), overrides: [
      groupSnapshotProvider(groupId).overrideWith((ref) async => snapshot),
    ]);

    // The banner title + body (en ARB values) render as Text nodes.
    expect(find.text('End-to-end encrypted group'), findsOneWidget);
    expect(
      find.text(
        'Messages are protected by end-to-end encryption. New members cannot see earlier messages.',
      ),
      findsOneWidget,
    );
    // The message body still renders (banner did not displace the list).
    expect(find.text('hi'), findsOneWidget);
  });
}
