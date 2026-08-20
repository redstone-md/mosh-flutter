// The attachment card inside a message, over all three conversation kinds:
// what it shows for each transfer state, and what its one action button
// does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentState;

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';
import '../shared/attachment_launcher_test_support.dart';

/// The card shows at most one action button, so this finds it.
Finder _action() => find.descendant(
      of: find.byType(AttachmentCard),
      matching: find.byType(IconButton),
    );

bool _actionEnabled(WidgetTester tester) =>
    tester.widget<IconButton>(_action()).onPressed != null;

void main() {
  for (final testCase in conversationCases()) {
    final label = testCase.label;

    testWidgets('$label: an offered file shows its name, size and state',
        (tester) async {
      final file = testAttachment(attachmentId: 'att-1');
      await pumpConversation(
        tester,
        testCase,
        messages: [TestMessage(body: 'here it is', attachment: file)],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-1',
            state: AttachmentState.offered,
          ),
        ],
      );

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.textContaining('1.5 KB'), findsOneWidget);
      expect(find.textContaining('Ready to download'), findsOneWidget);
    });

    testWidgets('$label: a downloading file shows progress', (tester) async {
      final file = testAttachment(
        attachmentId: 'att-2',
        fileName: 'video.mp4',
        mime: 'video/mp4',
        totalSize: 10485760,
      );
      await pumpConversation(
        tester,
        testCase,
        messages: [TestMessage(body: 'big clip', attachment: file)],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-2',
            state: AttachmentState.downloading,
            completedChunks: 5,
            chunkCount: 10,
          ),
        ],
      );

      expect(find.text('video.mp4'), findsOneWidget);
      expect(find.textContaining('Downloading 50%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('$label: a failed transfer says so', (tester) async {
      final file = testAttachment(
        attachmentId: 'att-3',
        fileName: 'archive.zip',
        mime: 'application/zip',
      );
      await pumpConversation(
        tester,
        testCase,
        messages: [TestMessage(body: 'this one broke', attachment: file)],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-3',
            state: AttachmentState.failed,
          ),
        ],
      );

      expect(find.textContaining('Transfer failed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
    });

    testWidgets(
        '$label: Download runs against this conversation and locks '
        'the button while it does', (tester) async {
      final gateway = ScriptableGateway()
        ..hold(GatewayMethod.downloadAttachment);
      final file = testAttachment(attachmentId: 'att-busy');
      await pumpConversation(
        tester,
        testCase,
        gateway: gateway,
        messages: [TestMessage(body: 'download this', attachment: file)],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-busy',
            state: AttachmentState.offered,
          ),
        ],
      );

      expect(_actionEnabled(tester), isTrue);

      await tester.tap(_action());
      await tester.pump();
      expect(_actionEnabled(tester), isFalse);

      final call = gateway.lastCall(GatewayMethod.downloadAttachment);
      expect(call?.target, testCase.target);
      expect(call?.arg<String>('attachmentId'), 'att-busy');

      gateway.release(GatewayMethod.downloadAttachment);
      await tester.pump();
      await tester.pump();
      expect(_actionEnabled(tester), isTrue);
    });

    testWidgets('$label: a downloaded file opens in the system app',
        (tester) async {
      final launcher = RecordingAttachmentLauncher();
      final file = testAttachment(attachmentId: 'att-external');
      await pumpConversation(
        tester,
        testCase,
        launcher: launcher,
        messages: [
          TestMessage.own(body: 'local report', attachment: file),
        ],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-external',
            direction: 'outgoing',
            state: AttachmentState.available,
            localPath: '/tmp/report.pdf',
          ),
        ],
      );

      await tester.tap(_action());
      await tester.pump();

      expect(launcher.paths, ['/tmp/report.pdf']);
    });

    testWidgets('$label: a failure to open is surfaced', (tester) async {
      final file = testAttachment(attachmentId: 'att-failure');
      await pumpConversation(
        tester,
        testCase,
        launcher:
            RecordingAttachmentLauncher(error: StateError('launcher failed')),
        messages: [
          TestMessage.own(body: 'local report', attachment: file),
        ],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-failure',
            direction: 'outgoing',
            state: AttachmentState.available,
            localPath: '/tmp/report.pdf',
          ),
        ],
      );

      await tester.tap(_action());
      await tester.pump();

      expect(find.text('launcher failed'), findsOneWidget);
    });

    testWidgets('$label: a file with no path on disk cannot be opened',
        (tester) async {
      final file = testAttachment(attachmentId: 'att-empty');
      await pumpConversation(
        tester,
        testCase,
        messages: [TestMessage.own(body: 'not local', attachment: file)],
        attachments: [
          testAttachmentView(
            attachmentId: 'att-empty',
            direction: 'outgoing',
            state: AttachmentState.available,
            localPath: '',
          ),
        ],
      );

      expect(_actionEnabled(tester), isFalse);
    });
  }
}
