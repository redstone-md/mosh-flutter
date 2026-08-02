// Unit + widget tests for the DM ConversationTools (message search +
// filter) port of the React desktop surface in
// `src/features/private-dm/ConversationTools.tsx` (`filterMessages`,
// `messageSearchText`, `ConversationTools`, `SearchEmpty`). The pure
// `filterDmMessages` helper is the `@visibleForTesting` seam driven
// directly by the eight logic cases below (1-1 with the React behavior);
// the single widget test pumps DmScreen with two messages (one carrying
// the attachment `report.pdf`, one plain `hello`), types `report` into
// the search field, and asserts only the attachment message renders --
// confirming the filter runs BEFORE grouping and the plain message is
// dropped from the visible set.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/session_providers.dart';

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

ChatMessage _msg({
  required String fromDevice,
  required String body,
  AttachmentDescriptor? attachment,
}) =>
    ChatMessage(
      fromDevice: fromDevice,
      body: body,
      messageId: null,
      sentAtMs: null,
      attachment: attachment,
      callEvent: null,
      deliveryStatus: null,
      deliveryError: null,
      retryable: null,
      retryCount: null,
    );

SessionSnapshot _snapshot({
  required String sessionId,
  required String displayName,
  required List<ChatMessage> messages,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: '',
      state: 'ready',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: '0123456789abcdef',
      messages: messages,
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

void main() {
  const sessionId = 'sess-tools';
  final alicePlain = _msg(fromDevice: 'alice', body: 'hello world');
  final bobPlain = _msg(fromDevice: 'bob', body: 'how are you');
  final aliceReport = _msg(
    fromDevice: 'alice',
    body: 'here is the report',
    attachment: _fileDescriptor(
      attachmentId: 'att-1',
      fileName: 'report.pdf',
      mime: 'application/pdf',
    ),
  );
  final bobVideo = _msg(
    fromDevice: 'bob',
    body: 'a clip',
    attachment: _fileDescriptor(
      attachmentId: 'att-2',
      fileName: 'clip.mp4',
      mime: 'video/mp4',
    ),
  );

  group('filterDmMessages', () {
    test('empty search + filter all returns all messages unchanged', () {
      final input = [alicePlain, bobPlain];
      final out = filterDmMessages(input, '', ConversationFilter.all);
      expect(out, equals(input));
    });

    test('empty search + filter attachments keeps only attachment messages',
        () {
      final input = [alicePlain, aliceReport, bobVideo];
      final out = filterDmMessages(input, '', ConversationFilter.attachments);
      expect(out, [aliceReport, bobVideo]);
    });

    test('search "alice" matches from_device case-insensitively', () {
      final input = [alicePlain, bobPlain, aliceReport];
      final out = filterDmMessages(input, 'alice', ConversationFilter.all);
      expect(out, [alicePlain, aliceReport]);
    });

    test('search "report" matches the attachment file_name', () {
      final input = [alicePlain, aliceReport];
      final out = filterDmMessages(input, 'report', ConversationFilter.all);
      expect(out, [aliceReport]);
    });

    test('search "pdf" matches the attachment mime', () {
      final input = [alicePlain, aliceReport];
      final out = filterDmMessages(input, 'pdf', ConversationFilter.all);
      expect(out, [aliceReport]);
    });

    test('search with surrounding whitespace is trimmed', () {
      final input = [alicePlain, bobPlain];
      final out = filterDmMessages(input, '  hello  ', ConversationFilter.all);
      expect(out, [alicePlain]);
    });

    test('search with no matches returns an empty list', () {
      final input = [alicePlain, bobPlain];
      final out =
          filterDmMessages(input, 'nonexistentterm', ConversationFilter.all);
      expect(out, isEmpty);
    });

    test('filter attachments + search "bob" keeps only Bob attachments', () {
      final input = [alicePlain, bobPlain, bobVideo];
      final out = filterDmMessages(
          input, 'bob', ConversationFilter.attachments);
      expect(out, [bobVideo]);
    });
  });

  // Widget test: two messages, one carrying `report.pdf` and one plain
  // `hello`. Typing `report` into the search field must filter the plain
  // message out so only the attachment message renders -- proving the
  // filter runs before grouping and the visible set shrinks.
  testWidgets('typing "report" hides the plain message', (tester) async {
    final snapshot = _snapshot(
      sessionId: sessionId,
      displayName: 'alice',
      messages: [
        _msg(fromDevice: 'bob', body: 'hello'),
        _msg(
          fromDevice: 'bob',
          body: 'see this',
          attachment: _fileDescriptor(
            attachmentId: 'att-1',
            fileName: 'report.pdf',
            mime: 'application/pdf',
          ),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeSessionProvider(sessionId)
            .overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DmScreen(sessionId: sessionId),
      ),
    ));
    await tester.pumpAndSettle();

    // Both messages render before any search.
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('see this'), findsOneWidget);

    // Type "report" into the ConversationTools search field.
    await tester.enterText(find.byType(TextField).first, 'report');
    await tester.pumpAndSettle();

    // The plain "hello" message is filtered out; the attachment message
    // body remains, and the attachment file name still renders.
    expect(find.text('hello'), findsNothing);
    expect(find.text('see this'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
  });

  // isMobileBreakpoint boundary -- 1-1 with React's `@media (max-width:
  // 580px)` (middle-column.css): width <= 580 is mobile, width > 580 is
  // desktop. The helper reads [MediaQuery.sizeOf] so the boundary is driven
  // purely by the width; each case overrides the inherited MediaQuery and
  // asserts the bool returned.
  group('isMobileBreakpoint', () {
    // Pumps a Builder whose context has a MediaQuery overridden to the
    // given width; the builder writes the [isMobileBreakpoint] result into
    // [captured] so the test can assert it.
    Future<void> pumpAtWidth(
      WidgetTester tester,
      double width, {
      required ValueNotifier<bool?> captured,
    }) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              captured.value = isMobileBreakpoint(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('width 580 -> mobile (CSS max-width: 580px includes 580)',
        (tester) async {
      final captured = ValueNotifier<bool?>(null);
      await pumpAtWidth(tester, 580, captured: captured);
      expect(captured.value, isTrue);
    });

    testWidgets('width 581 -> desktop', (tester) async {
      final captured = ValueNotifier<bool?>(null);
      await pumpAtWidth(tester, 581, captured: captured);
      expect(captured.value, isFalse);
    });

    testWidgets('width 400 -> mobile', (tester) async {
      final captured = ValueNotifier<bool?>(null);
      await pumpAtWidth(tester, 400, captured: captured);
      expect(captured.value, isTrue);
    });

    testWidgets('width 800 -> desktop', (tester) async {
      final captured = ValueNotifier<bool?>(null);
      await pumpAtWidth(tester, 800, captured: captured);
      expect(captured.value, isFalse);
    });
  });
}
