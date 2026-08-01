// Widget tests for the channel message-row avatar slot (React `.avatar` +
// `avatar avatar-spacer` parity), mirroring the dm row's avatar test.
// Pumps `ChannelMessageRow` directly inside `MaterialApp` (the row is a
// pure `StatelessWidget` -- no providers, no async) and asserts:
//   - a non-grouped PEER row renders one `CircleAvatar` whose initials
//     match `avatarInitials(fromDevice)`,
//   - a grouped peer row renders NO `CircleAvatar` (the slot is a plain
//     `SizedBox` spacer),
//   - a non-grouped OWN row renders one `CircleAvatar` with own initials.
// The avatar sits OUTSIDE the bubble's 75%-width `ConstrainedBox` as a
// separate flex item (React `message-row { display:flex; gap:12px }`); the
// left/right side is asserted only loosely (presence + correct initials)
// since precise side-assertion is brittle under `MaterialApp` padding.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/channel/channel_message_row.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/rust/channel_runtime.dart';

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

Widget _wrap(ChannelMessageRow row) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: row),
    );

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  testWidgets(
      'non-grouped peer channel row renders a CircleAvatar with peer initials',
      (tester) async {
    await tester.pumpWidget(_wrap(ChannelMessageRow(
      message: _msg(
        fromDevice: 'bob',
        fromFingerprint: 'fp-bob',
        body: 'hi',
        sentAtMs: BigInt.from(1700000000000),
      ),
      ownFingerprint: 'fp-me',
      grouped: false,
      onAttachmentDownload: (_) {},
      onAttachmentCancel: (_) {},
      onAttachmentOpen: (_) {},
      onRetry: (_) {},
      l: l,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text(avatarInitials('bob')), findsOneWidget);
  });

  testWidgets('grouped peer channel row renders NO CircleAvatar (spacer only)',
      (tester) async {
    await tester.pumpWidget(_wrap(ChannelMessageRow(
      message: _msg(
        fromDevice: 'bob',
        fromFingerprint: 'fp-bob',
        body: 'hi2',
        sentAtMs: BigInt.from(1700000000000),
      ),
      ownFingerprint: 'fp-me',
      grouped: true,
      onAttachmentDownload: (_) {},
      onAttachmentCancel: (_) {},
      onAttachmentOpen: (_) {},
      onRetry: (_) {},
      l: l,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets(
      'non-grouped own channel row renders a CircleAvatar with own initials',
      (tester) async {
    await tester.pumpWidget(_wrap(ChannelMessageRow(
      message: _msg(
        fromDevice: 'me',
        fromFingerprint: 'fp-me',
        body: 'mine',
        sentAtMs: BigInt.from(1700000000000),
      ),
      ownFingerprint: 'fp-me',
      grouped: false,
      onAttachmentDownload: (_) {},
      onAttachmentCancel: (_) {},
      onAttachmentOpen: (_) {},
      onRetry: (_) {},
      l: l,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text(avatarInitials('me')), findsOneWidget);
  });
}
