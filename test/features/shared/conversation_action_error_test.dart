// A shared action that fails with a typed bridge error shows the treatment
// its kind names, never the runtime's diagnostic sentence and never the
// Dart type name.
//
// The errors cross the seam as the real generated `ConversationBridgeError`
// -- the same type RealBridgeGateway throws -- scripted through the
// gateway double. Retryable message delivery, rejoin and revocation stay
// snapshot-driven; those tests live in their own files.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/attachment_card.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentState;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

const _bridgeDetail = 'runtime diagnostic text';

ConversationBridgeError _bridgeError(ConversationBridgeErrorKind kind) =>
    ConversationBridgeError(kind: kind, message: _bridgeDetail);

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ConversationComposer)))!;

Future<void> _sendText(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(ConversationComposer),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(kComposerSendButtonKey));
  await tester.pumpAndSettle();
}

ChatErrorBanner _banner(WidgetTester tester) =>
    tester.widget<ChatErrorBanner>(find.byType(ChatErrorBanner));

String _bannerText(WidgetTester tester) => _banner(tester).message;

/// The screen's controller, reached the way the composer and the cards
/// reach it, for the actions no test can drive through a real file pick.
ConversationController _controller(
  WidgetTester tester,
  ConversationCase testCase,
) =>
    ProviderScope.containerOf(tester.element(find.byType(ConversationComposer)))
        .read(conversationControllerProvider(testCase.target).notifier);

/// What each kind says, from the spec of the taxonomy: the sentence the
/// kind names, with the detail only where the kind alone says nothing.
Map<ConversationBridgeErrorKind, String> _wordingByKind(AppLocalizations l) => {
      ConversationBridgeErrorKind.invalidInput:
          l.chatActionErrorInvalidInput(_bridgeDetail),
      ConversationBridgeErrorKind.unavailable: l.chatActionErrorUnavailable,
      ConversationBridgeErrorKind.notReady: l.chatActionErrorNotReady,
      ConversationBridgeErrorKind.missingConversation:
          l.chatActionErrorMissingConversation,
      ConversationBridgeErrorKind.missingMessage:
          l.chatActionErrorMissingMessage,
      ConversationBridgeErrorKind.missingAttachment:
          l.chatActionErrorMissingAttachment,
      ConversationBridgeErrorKind.transfer: l.chatActionErrorTransfer,
      ConversationBridgeErrorKind.persistence: l.chatActionErrorPersistence,
      ConversationBridgeErrorKind.needsRejoin: l.chatActionErrorNeedsRejoin,
      ConversationBridgeErrorKind.revoked: l.chatActionErrorRevoked,
      ConversationBridgeErrorKind.internal:
          l.chatActionErrorInternal(_bridgeDetail),
    };

void main() {
  for (final testCase in conversationCases()) {
    testWidgets(
        '${testCase.label}: a persistence failure on send says so by kind',
        (tester) async {
      final gateway = ScriptableGateway()
        ..failNext(
          GatewayMethod.send,
          error: _bridgeError(ConversationBridgeErrorKind.persistence),
        );
      await pumpConversation(tester, testCase, gateway: gateway);

      await _sendText(tester, 'hello');

      expect(_bannerText(tester), _l(tester).chatActionErrorPersistence);
      expect(find.textContaining(_bridgeDetail), findsNothing);
      expect(find.textContaining('Instance of'), findsNothing);
    });
  }

  final dm = conversationCases().first;

  testWidgets(
      'every kind has its own wording on send, and text only where '
      'the kind says nothing', (tester) async {
    final gateway = ScriptableGateway();
    await pumpConversation(tester, dm, gateway: gateway);
    final wording = _wordingByKind(_l(tester));
    expect(wording.keys, containsAll(ConversationBridgeErrorKind.values));

    for (final kind in ConversationBridgeErrorKind.values) {
      gateway.failNext(GatewayMethod.send, error: _bridgeError(kind));
      await _sendText(tester, 'hello $kind');
      expect(_bannerText(tester), wording[kind], reason: '$kind');
    }
  });

  testWidgets('a failed file send says so by kind and offers no Retry',
      (tester) async {
    final gateway = ScriptableGateway()
      ..failNext(
        GatewayMethod.sendAttachment,
        error: _bridgeError(ConversationBridgeErrorKind.transfer),
      );
    await pumpConversation(tester, dm, gateway: gateway);

    await _controller(tester, dm).sendAttachment(const PickedAttachment(
      fileName: 'a.txt',
      mime: 'text/plain',
      dataBase64: 'aGk=',
    ));
    await tester.pumpAndSettle();

    expect(_bannerText(tester), _l(tester).chatActionErrorTransfer);
    expect(_banner(tester).onRetry, isNull);
  });

  testWidgets('a failed download says so by kind', (tester) async {
    final gateway = ScriptableGateway()
      ..failNext(
        GatewayMethod.downloadAttachment,
        error: _bridgeError(ConversationBridgeErrorKind.missingAttachment),
      );
    await pumpConversation(
      tester,
      dm,
      gateway: gateway,
      messages: [
        TestMessage(
          body: 'file',
          attachment: testAttachment(attachmentId: 'att-gone'),
        ),
      ],
      attachments: [
        testAttachmentView(
          attachmentId: 'att-gone',
          state: AttachmentState.offered,
        ),
      ],
    );

    await tester.tap(find.descendant(
      of: find.byType(AttachmentCard),
      matching: find.byType(IconButton),
    ));
    await tester.pumpAndSettle();

    expect(gateway.countOf(GatewayMethod.downloadAttachment), 1);
    expect(_bannerText(tester), _l(tester).chatActionErrorMissingAttachment);
  });

  testWidgets('a failed message retry says so by kind', (tester) async {
    final gateway = ScriptableGateway()
      ..failNext(
        GatewayMethod.retry,
        error: _bridgeError(ConversationBridgeErrorKind.missingMessage),
      );
    await pumpConversation(
      tester,
      dm,
      gateway: gateway,
      messages: [
        TestMessage.own(
          body: 'boom',
          messageId: 'm-1',
          sentAtMs: BigInt.from(1700000000000),
          deliveryStatus: MessageDeliveryStatus.failed,
          deliveryError: 'peer offline',
          retryable: true,
        ),
      ],
    );

    await tester.tap(find.text(_l(tester).chatErrorRetry));
    await tester.pumpAndSettle();

    expect(_bannerText(tester), _l(tester).chatActionErrorMissingMessage);
  });

  testWidgets('a failed leave stays on the screen and says so by kind',
      (tester) async {
    final gateway = ScriptableGateway()
      ..failNext(
        GatewayMethod.leave,
        error: _bridgeError(ConversationBridgeErrorKind.unavailable),
      );
    await pumpConversation(tester, dm, gateway: gateway, useRouter: true);

    await tester.tap(find.byIcon(dm.leaveIcon));
    await tester.pumpAndSettle();
    await tester.tap(find.text(dm.leaveConfirmLabel));
    await tester.pumpAndSettle();

    expect(gateway.countOf(GatewayMethod.leave), 1);
    expect(find.byType(ConversationComposer), findsOneWidget);
    expect(_bannerText(tester), _l(tester).chatActionErrorUnavailable);
  });
}
