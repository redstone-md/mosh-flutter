import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';

import '../../support/conversation_cases.dart';

void main() {
  for (final conversation in conversationCases()) {
    testWidgets(
        '${conversation.label}: a late preview error survives closing the chat',
        (tester) async {
      await pumpConversation(tester, conversation);
      final report = tester
          .widget<AttachmentPicker>(find.byType(AttachmentPicker))
          .onError;
      await tester.pumpWidget(const SizedBox());
      report(AttachmentPickError.previewUnavailable);
      expect(tester.takeException(), isNull);
    });
  }
}
