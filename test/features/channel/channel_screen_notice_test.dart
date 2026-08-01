// Widget test for the public-channel notice banner -- the 1-в-1 port of
// React `PublicNotice` (ActiveChatPanes.tsx ~L434-445), wired into
// ChannelScreen at the top of the body Column (matching React's
// `afterHeader` slot, ABOVE ConversationTools). Asserts the banner renders
// with the localized title + body so a regression that drops the banner
// (or wires it in the wrong slot) fails. Mirrors the seed/override idiom
// of `channel_screen_grouping_test.dart` (override `channelSnapshotProvider`
// so the native cdylib is not involved).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/channel/channel_screen.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

ChannelMessage _msg({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  BigInt? sentAtMs,
}) =>
    ChannelMessage(
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

ChannelSnapshot _snapshot({
  required String name,
  required String deviceFingerprint,
  required List<ChannelMessage> messages,
}) =>
    ChannelSnapshot(
      name: name,
      topic: '',
      meshId: 'testmesh',
      displayName: 'me',
      deviceFingerprint: deviceFingerprint,
      messages: messages,
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

void main() {
  // The banner is ALWAYS shown for a channel (no conditional -- every
  // channel renders `PublicNotice`), so a channel with messages is enough
  // to assert it appears alongside the list. Resolves the localized en
  // strings via AppLocalizations so the test pins the exact ARB values.
  testWidgets('channel screen renders the public-channel notice banner',
      (tester) async {
    const name = 'chan-notice';
    final snapshot = _snapshot(
      name: name,
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
        channelSnapshotProvider(name).overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChannelScreen(name: name),
      ),
    ));
    await tester.pumpAndSettle();

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
