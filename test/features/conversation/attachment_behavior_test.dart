import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_shared_file.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_state.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/conversation_cases.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

const _target = DmTarget('attachment-policy');

ProviderContainer _container(ScriptableGateway gateway) => ProviderContainer(
      overrides: [
        gatewayProvider.overrideWithValue(gateway),
        bridgeFacadeProvider.overrideWithValue(
            ScriptableBridge(conversations: gateway.conversations)),
      ],
    );

void main() {
  for (final terminal in [AttachmentState.failed, AttachmentState.cancelled]) {
    test('a $terminal transfer drops a waiting open despite its cached path',
        () {
      final gateway = ScriptableGateway();
      final container = _container(gateway);
      addTearDown(container.dispose);
      final controller =
          container.read(conversationControllerProvider(_target).notifier);
      final image = testAttachment(
          attachmentId: 'image', fileName: 'image.png', mime: 'image/png');
      controller.openAttachment(image, null, own: false);

      final outcome = controller.resolvePendingOpen([
        testAttachmentView(
            attachmentId: 'image',
            state: terminal,
            localPath: '/tmp/old-image.png'),
      ]);

      expect(outcome, isA<ConversationPendingDropped>());
      expect(
          container.read(conversationControllerProvider(_target)).pendingOpen,
          isNull);
    });
  }

  test('opening an image already downloading does not request it again', () {
    final gateway = ScriptableGateway();
    final container = _container(gateway);
    addTearDown(container.dispose);
    final controller =
        container.read(conversationControllerProvider(_target).notifier);
    final image = testAttachment(
        attachmentId: 'image', fileName: 'image.png', mime: 'image/png');

    controller.openAttachment(
        image,
        testAttachmentView(
            attachmentId: 'image', state: AttachmentState.downloading),
        own: false);

    expect(gateway.countOf(GatewayMethod.downloadAttachment), 0);
    expect(container.read(conversationControllerProvider(_target)).pendingOpen,
        image);
  });

  // Regression (CodeAnt PR #6): a press on a paused picture's preview opened
  // it, starting its download past the button that waits for another one.
  testWidgets('a paused picture waits for another transfer on its preview too',
      (tester) async {
    var opened = 0;
    await pumpScreen(
        tester,
        Scaffold(
            body: Center(
          child: AttachmentCard(
              descriptor: AttachmentDescriptor(
                attachmentId: 'photo',
                contentHash: 'h-photo',
                fileName: 'photo.png',
                mime: 'image/png',
                totalSize: BigInt.from(4096),
                thumbnailB64:
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
                    'EQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
              ),
              view: testAttachmentView(
                  attachmentId: 'photo', state: AttachmentState.paused),
              own: false,
              busy: true,
              onDownload: (_) {},
              onCancel: (_) {},
              onOpen: (_) => opened++),
        )));

    // A corner of the preview, away from the resume control at its centre.
    await tester.tapAt(
        tester.getTopLeft(find.bySemanticsLabel('Open photo.png')) +
            const Offset(8, 8));

    expect(opened, 0);
    // Regression (CodeAnt PR #201): a screen reader still announced the
    // inert preview as a button it could press.
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(find.bySemanticsLabel('Open photo.png')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false));
    semantics.dispose();
  });

  testWidgets(
      'unknown transfer progress is indeterminate on both file surfaces',
      (tester) async {
    final file = testAttachment(attachmentId: 'file');
    final view = testAttachmentView(
        attachmentId: 'file', state: AttachmentState.downloading);
    final actions = ConversationAttachmentCallbacks(
        busy: false, onDownload: (_) {}, onCancel: (_) {}, onOpen: (_) {});
    await pumpScreen(
        tester,
        Scaffold(
            body: Column(children: [
          AttachmentCard(
              descriptor: file,
              view: view,
              own: false,
              busy: false,
              onDownload: actions.onDownload,
              onCancel: actions.onCancel,
              onOpen: actions.onOpen),
          ConversationSharedFile(
              message: ConversationMessage(
                  fromDevice: 'peer', body: '', own: false, attachment: file),
              view: view,
              actions: actions),
        ])),
        settle: false);

    final indicators = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(indicators, hasLength(2));
    expect(indicators.map((indicator) => indicator.value), [null, null]);
  });
}
