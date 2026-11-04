import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/rust/conversation/read_marks.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

const _divider = 'Unread messages';

List<TestMessage> _messages(int count) => [
      for (var i = 0; i < count; i++)
        TestMessage(
          body: 'Message $i',
          messageId: 'm$i',
          sentAtMs: BigInt.from(1700000000000 + i * 1000),
        ),
    ];

Future<ProviderContainer> _open(
  WidgetTester tester,
  ConversationCase testCase,
  List<TestMessage> messages,
  UnreadState? Function() unread,
) async {
  final gateway = ScriptableGateway();
  final container = ProviderContainer(overrides: [
    gatewayProvider.overrideWithValue(gateway),
    bridgeFacadeProvider.overrideWithValue(
        ScriptableBridge(conversations: gateway.conversations)),
    testCase.snapshotOverride(messages: messages, unread: unread),
  ]);
  addTearDown(container.dispose);
  await pumpScreen(tester, testCase.screen, container: container);
  return container;
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  final testCase = conversationCases().first;

  testWidgets('the divider stays above the first unread after viewing',
      (tester) async {
    UnreadState? reported =
        const UnreadState(count: 2, firstUnreadMessageId: 'm1');
    final container =
        await _open(tester, testCase, _messages(3), () => reported);
    expect(_top(tester, 'Message 0'), lessThan(_top(tester, _divider)));
    expect(_top(tester, _divider), lessThan(_top(tester, 'Message 1')));

    reported = const UnreadState(count: 0);
    container.invalidate(conversationSnapshotProvider(testCase.target));
    await tester.pumpAndSettle();

    expect(find.text(_divider), findsOneWidget,
        reason: 'viewing clears the count, not the divider on screen');
  });

  testWidgets('a far unread divider is scrolled into view on open',
      (tester) async {
    await _open(
      tester,
      testCase,
      _messages(80),
      () => const UnreadState(count: 75, firstUnreadMessageId: 'm5'),
    );

    final divider = tester.getRect(find.text(_divider));
    final list = tester.getRect(find.byType(ListView));
    expect(list.contains(divider.center), isTrue);
    expect(find.text('Message 5'), findsOneWidget);
  });

  testWidgets('a filter that hides the first unread keeps the newest in view',
      (tester) async {
    final messages = [
      for (var i = 0; i < 80; i++)
        ConversationMessage(
          fromDevice: 'peer',
          body: 'Message $i',
          own: false,
          messageId: 'm$i',
          sentAtMs: BigInt.from(1700000000000 + i * 1000),
        ),
    ];
    await pumpScreen(
      tester,
      ConversationMessageListView(
        messages: messages.sublist(10),
        snapshot: DmConversation(
            const DmTarget('s1'), TestSnapshots.dm(sessionId: 's1')),
        firstUnreadId: 'm5',
        attachmentCallbacks: (_, {required bool own}) =>
            ConversationAttachmentCallbacks(
          busy: false,
          onDownload: (_) {},
          onCancel: (_) {},
          onOpen: (_) {},
        ),
        onRetryMessage: (_) {},
      ),
    );

    expect(find.text('Message 79'), findsOneWidget);
  });
}
