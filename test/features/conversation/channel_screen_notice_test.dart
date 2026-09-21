// Widget test for the public-channel notice banner wired into ChannelScreen
// at the top of the body Column, above ConversationTools. Asserts the
// banner renders with the localized title + body so a regression that drops
// the banner (or wires it in the wrong slot) fails. Overrides
// `channelSnapshotProvider` so the native cdylib is not involved.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/channel_screen.dart';
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';

void main() {
  // The banner is always shown for a channel, so a channel with messages is
  // enough to assert it appears alongside the list. Resolves the localized
  // en strings via AppLocalizations so the test pins the exact ARB values.
  testWidgets('channel screen renders the public-channel notice banner',
      (tester) async {
    const name = 'chan-notice';
    final snapshot = TestSnapshots.channel(
      name: name,
      deviceFingerprint: 'fp-me',
      messages: [
        TestMessages.channel(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'hi',
          sentAtMs: BigInt.from(1700000000000),
        ),
      ],
    );

    await pumpScreen(tester, const ChannelScreen(name: name), overrides: [
      channelSnapshotProvider(name).overrideWith((ref) async => snapshot),
    ]);

    // The banner title + body (en ARB values) render as Text nodes.
    expect(find.text('Public channel'), findsOneWidget);
    expect(
      find.text(
        'Not end-to-end encrypted. Anyone who joins this channel can read messages. Your device fingerprint is shown next to each message you publish.',
      ),
      findsOneWidget,
    );
    // The message body still renders (banner did not displace the list).
    expect(find.text('hi'), findsOneWidget);
  });
}
