import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'conversation_cases.dart';

void main() {
  for (final testCase in conversationCases().take(2)) {
    testWidgets('${testCase.label} harness loads names without a native bridge',
        (tester) async {
      await pumpConversation(tester, testCase);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ConversationScreen)));
      final names = await container.read(chatNamesProvider.future);
      expect(names.entries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
