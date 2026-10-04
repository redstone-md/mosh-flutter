import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/conversation_cases.dart';
import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

Future<void> _changeSearchAndFilter(WidgetTester tester) async {
  if (find.byType(ConversationSearchBox).evaluate().isEmpty) {
    await tester.tap(find.byType(MobileSearchToggle));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.descendant(
      of: find.byType(ConversationSearchBox),
      matching: find.byType(TextField),
    ),
    'new search',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Files'));
  await tester.pumpAndSettle();
}

void main() {
  for (final testCase in conversationCases()) {
    testWidgets('${testCase.label}: UI changes do not repeat a view mark',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase,
          gateway: gateway, messages: const [TestMessage(body: 'hello')]);

      expect(gateway.callsTo(GatewayMethod.markViewed).single.target,
          testCase.target);
      await _changeSearchAndFilter(tester);
      expect(gateway.countOf(GatewayMethod.markViewed), 1);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConversationTools)),
      );
      container.invalidate(conversationSnapshotProvider(testCase.target));
      await container
          .read(conversationSnapshotProvider(testCase.target).future);
      await tester.pumpAndSettle();
      expect(gateway.countOf(GatewayMethod.markViewed), greaterThan(1));
      final afterRefresh = gateway.countOf(GatewayMethod.markViewed);
      await _changeSearchAndFilter(tester);
      expect(gateway.countOf(GatewayMethod.markViewed), afterRefresh);
    });

    testWidgets('${testCase.label}: a cached snapshot is marked only once',
        (tester) async {
      final gateway = ScriptableGateway();
      final container = ProviderContainer(overrides: [
        gatewayProvider.overrideWithValue(gateway),
        testCase.snapshotOverride(messages: const [TestMessage(body: 'hello')]),
      ]);
      addTearDown(container.dispose);
      await container
          .read(conversationSnapshotProvider(testCase.target).future);
      await pumpScreen(tester, testCase.screen, container: container);

      expect(gateway.callsTo(GatewayMethod.markViewed).single.target,
          testCase.target);
      await _changeSearchAndFilter(tester);
      expect(gateway.countOf(GatewayMethod.markViewed), 1);
    });
  }

  testWidgets('a reused screen marks the new cached conversation',
      (tester) async {
    final first = conversationCases(dmId: 'first').first;
    final second = conversationCases(dmId: 'second').first;
    final gateway = ScriptableGateway();
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(gateway),
      first.snapshotOverride(messages: const [TestMessage(body: 'hello')]),
      second.snapshotOverride(messages: const [TestMessage(body: 'hello')]),
    ]);
    addTearDown(container.dispose);
    await container.read(conversationSnapshotProvider(first.target).future);
    await container.read(conversationSnapshotProvider(second.target).future);
    var current = first.screen;
    late StateSetter setScreen;
    await pumpScreen(
      tester,
      StatefulBuilder(builder: (_, setState) {
        setScreen = setState;
        return current;
      }),
      container: container,
    );

    setScreen(() => current = second.screen);
    await tester.pumpAndSettle();

    expect(gateway.callsTo(GatewayMethod.markViewed).map((call) => call.target),
        [first.target, second.target]);
    await _changeSearchAndFilter(tester);
    expect(gateway.countOf(GatewayMethod.markViewed), 2);
  });
}
