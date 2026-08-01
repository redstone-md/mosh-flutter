// Unit + widget tests for the group ConversationTools (message search +
// filter) port of the React desktop surface in
// `src/features/private-dm/ConversationTools.tsx` (`filterMessages`,
// `messageSearchText`). The pure `filterGroupMessages` helper delegates to
// the shared generic `filterMessages` (lib/src/features/dm/
// conversation_tools.dart); these tests pin the group-typed seam with the
// same eight logic cases the DM `conversation_tools_test.dart` uses, plus a
// fingerprint-search regression asserting `fromFingerprint` is NOT part of
// the searchable text (React `GroupChatList` calls the generic
// `filterMessages`, whose `messageSearchText` joins only `from_device`,
// `body`, `attachment.file_name`, `attachment.mime`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/group/group_message_row.dart';
import 'package:mosh/src/features/group/group_screen.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

AttachmentDescriptor _fileDescriptor({
  required String attachmentId,
  required String fileName,
  required String mime,
}) =>
    AttachmentDescriptor(
      attachmentId: attachmentId,
      contentHash: 'h-$attachmentId',
      fileName: fileName,
      mime: mime,
      totalSize: BigInt.from(1024),
      thumbnailB64: null,
      voice: null,
    );

GroupMessage _msg({
  required String fromDevice,
  required String fromFingerprint,
  required String body,
  AttachmentDescriptor? attachment,
}) =>
    GroupMessage(
      fromDevice: fromDevice,
      fromFingerprint: fromFingerprint,
      body: body,
      messageId: null,
      sentAtMs: null,
      attachment: attachment,
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
  const groupId = 'group-tools';
  final alicePlain = _msg(
      fromDevice: 'alice', fromFingerprint: 'fp-alice', body: 'hello world');
  final bobPlain =
      _msg(fromDevice: 'bob', fromFingerprint: 'fp-bob', body: 'how are you');
  final aliceReport = _msg(
    fromDevice: 'alice',
    fromFingerprint: 'fp-alice',
    body: 'here is the report',
    attachment: _fileDescriptor(
        attachmentId: 'att-1', fileName: 'report.pdf', mime: 'application/pdf'),
  );
  final bobVideo = _msg(
    fromDevice: 'bob',
    fromFingerprint: 'fp-bob',
    body: 'a clip',
    attachment: _fileDescriptor(
        attachmentId: 'att-2', fileName: 'clip.mp4', mime: 'video/mp4'),
  );

  group('filterGroupMessages', () {
    test('empty search + filter all returns all messages unchanged', () {
      final input = [alicePlain, bobPlain];
      final out = filterGroupMessages(input, '', ConversationFilter.all);
      expect(out, equals(input));
    });

    test('empty search + filter attachments keeps only attachment messages',
        () {
      final input = [alicePlain, aliceReport, bobVideo];
      final out =
          filterGroupMessages(input, '', ConversationFilter.attachments);
      expect(out, [aliceReport, bobVideo]);
    });

    test('search "alice" matches from_device case-insensitively', () {
      final input = [alicePlain, bobPlain, aliceReport];
      final out = filterGroupMessages(input, 'alice', ConversationFilter.all);
      expect(out, [alicePlain, aliceReport]);
    });

    test('search "report" matches the attachment file_name', () {
      final input = [alicePlain, aliceReport];
      final out = filterGroupMessages(input, 'report', ConversationFilter.all);
      expect(out, [aliceReport]);
    });

    test('search "pdf" matches the attachment mime', () {
      final input = [alicePlain, aliceReport];
      final out = filterGroupMessages(input, 'pdf', ConversationFilter.all);
      expect(out, [aliceReport]);
    });

    test('search with surrounding whitespace is trimmed', () {
      final input = [alicePlain, bobPlain];
      final out =
          filterGroupMessages(input, '  hello  ', ConversationFilter.all);
      expect(out, [alicePlain]);
    });

    test('search with no matches returns an empty list', () {
      final input = [alicePlain, bobPlain];
      final out =
          filterGroupMessages(input, 'nonexistentterm', ConversationFilter.all);
      expect(out, isEmpty);
    });

    test('filter attachments + search "bob" keeps only Bob attachments', () {
      final input = [alicePlain, bobPlain, bobVideo];
      final out =
          filterGroupMessages(input, 'bob', ConversationFilter.attachments);
      expect(out, [bobVideo]);
    });

    test('search does NOT match fromFingerprint (generic search text)', () {
      // React `GroupChatList` calls the generic `filterMessages`, whose
      // `messageSearchText` joins only from_device + body + attachment
      // file_name/mime -- NOT from_fingerprint. Searching the fingerprint
      // value must therefore find nothing even though the fingerprint is
      // visible in the row's sender meta.
      final input = [
        _msg(
            fromDevice: 'carol',
            fromFingerprint: 'fp-secret-fp',
            body: 'nothing here'),
      ];
      final out =
          filterGroupMessages(input, 'fp-secret', ConversationFilter.all);
      expect(out, isEmpty);
    });
  });

  // Widget test: two group messages, one carrying `report.pdf` and one
  // plain `hello`. Typing `report` into the search field must filter the
  // plain message out so only the attachment message renders -- proving the
  // filter runs before grouping and the visible set shrinks.
  testWidgets('typing "report" hides the plain group message', (tester) async {
    final snapshot = _snapshot(
      groupId: groupId,
      deviceFingerprint: 'fp-me',
      messages: [
        _msg(fromDevice: 'bob', fromFingerprint: 'fp-bob', body: 'hello'),
        _msg(
          fromDevice: 'bob',
          fromFingerprint: 'fp-bob',
          body: 'see this',
          attachment: _fileDescriptor(
              attachmentId: 'att-1',
              fileName: 'report.pdf',
              mime: 'application/pdf'),
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

    // Both messages render before any search.
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('see this'), findsOneWidget);

    // Type "report" into the ConversationTools search field (the first
    // TextField on the screen is the search input, before the composer).
    await tester.enterText(find.byType(TextField).first, 'report');
    await tester.pumpAndSettle();

    // The plain "hello" message is filtered out; the attachment message
    // body remains (its searchable text includes the file_name
    // "report.pdf"). The group row does not yet render an AttachmentCard,
    // so only the body is asserted -- the point of this test is the
    // filter-before-group behavior, not the attachment UI.
    expect(find.text('hello'), findsNothing);
    expect(find.text('see this'), findsOneWidget);
  });
}
