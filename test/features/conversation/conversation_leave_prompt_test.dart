import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_leave_prompt.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

import '../../support/pump.dart';

void main() {
  testWidgets(
    'unresolved conversations never expose raw IDs in confirmations',
    (tester) async {
      await pumpScreen(
        tester,
        Builder(
          builder: (context) {
            final l = AppLocalizations.of(context)!;
            return Column(
              children: [
                Text(
                  ConversationLeavePrompt.of(
                    l,
                    const DmTarget('session-raw-id'),
                    null,
                  ).title,
                ),
                Text(
                  ConversationLeavePrompt.of(
                    l,
                    const GroupTarget('group-raw-id'),
                    null,
                  ).title,
                ),
              ],
            );
          },
        ),
      );
      expect(find.text('Delete this chat?'), findsOneWidget);
      expect(find.text('Leave this group?'), findsOneWidget);
    },
  );
}
