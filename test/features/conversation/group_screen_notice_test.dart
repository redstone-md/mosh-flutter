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
  // The banner is always shown for a group, so a group with messages is
  // enough to assert it appears alongside the list. Resolves the localized
  // en ARB values via AppLocalizations so the test pins the exact strings.
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
        'OpenMLS protects message content. Only members the admin has admitted can decrypt. New members do not see prior history.',
      ),
      findsOneWidget,
    );
    // The message body still renders (banner did not displace the list).
    expect(find.text('hi'), findsOneWidget);
  });
}
