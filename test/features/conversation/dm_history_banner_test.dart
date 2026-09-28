import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_banners.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'history status waits for a source, imports, then hides after completion',
      (tester) async {
    for (final state in [
      DmHistorySyncState.waitingForSource,
      DmHistorySyncState.importing,
      DmHistorySyncState.complete,
      null
    ]) {
      await pumpScreen(
          tester,
          ConversationBanners(
            target: const DmTarget('history'),
            snapshot: DmConversation(const DmTarget('history'),
                TestSnapshots.dm(sessionId: 'history', historySync: state)),
          ));
      expect(
          find.text('Waiting for message history'),
          state == DmHistorySyncState.waitingForSource
              ? findsOneWidget
              : findsNothing);
      expect(
          find.text('Importing message history'),
          state == DmHistorySyncState.importing
              ? findsOneWidget
              : findsNothing);
    }
  });
}
