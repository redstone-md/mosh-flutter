// Widget tests for the group message-row avatar slot (React `.avatar` +
// `avatar avatar-spacer` parity), mirroring the dm + channel row avatar
// tests. Pumps `GroupMessageRow` directly inside `MaterialApp` (the row is
// a pure `StatelessWidget` -- no providers, no async) and asserts:
//   - a non-grouped PEER row renders one `CircleAvatar` whose initials
//     match `avatarInitials(fromDevice)`,
//   - a grouped peer row renders NO `CircleAvatar` (the slot is a plain
//     `SizedBox` spacer),
//   - a non-grouped OWN row renders one `CircleAvatar` with own initials.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';
import 'package:mosh/src/features/group/group_message_row.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

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

Widget _wrap(GroupMessageRow row) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: row),
    );

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  testWidgets(
      'non-grouped peer group row renders a CircleAvatar with peer initials',
      (tester) async {
    await tester.pumpWidget(_wrap(GroupMessageRow(
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

  testWidgets('grouped peer group row renders NO CircleAvatar (spacer only)',
      (tester) async {
    await tester.pumpWidget(_wrap(GroupMessageRow(
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
      'non-grouped own group row renders a CircleAvatar with own initials',
      (tester) async {
    await tester.pumpWidget(_wrap(GroupMessageRow(
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
