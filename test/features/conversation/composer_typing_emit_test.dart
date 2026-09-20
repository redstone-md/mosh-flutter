// The [[Typing indicator]] emit contract on the composer (issue #2,
// ticket #6): a growing draft fires onTyping on every keystroke (the
// runtime throttles repeats), and a draft cleared back to empty fires
// nothing — an empty draft is not typing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show PickedAttachment;
import 'package:mosh/src/features/shared/voice_composer.dart' show VoiceSend;

void main() {
  void noAttach(PickedAttachment _) {}

  void noVoice(VoiceSend _) {}

  Future<void> pump(
    WidgetTester tester, {
    required TextEditingController c,
    required List<String> typing,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationComposer(
          controller: c,
          sending: false,
          disabled: false,
          placeholder: 'p',
          sendLabel: 'Send',
          onSend: () {},
          onTyping: () => typing.add('tick'),
          attachLabel: 'a',
          onAttach: noAttach,
          onAttachmentPickError: (_) {},
          voiceRecordLabel: 'r',
          voiceDiscardLabel: 'd',
          voiceStopLabel: 's',
          voicePlayLabel: 'pl',
          voiceSendLabel: 'vs',
          onSendVoice: noVoice,
          onVoiceError: (_) {},
        ),
      ),
    ));
  }

  testWidgets('every keystroke on a growing draft fires the typing signal',
      (tester) async {
    final controller = TextEditingController();
    final typing = <String>[];
    await pump(tester, c: controller, typing: typing);

    await tester.enterText(find.byType(TextField), 'h');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();

    // Per-keystroke is the contract: the runtime owns the ~3 s throttle,
    // so the composer must not batch or gate.
    expect(typing, hasLength(2));
    controller.dispose();
  });

  testWidgets('clearing the draft back to empty fires nothing',
      (tester) async {
    final controller = TextEditingController(text: 'hi');
    final typing = <String>[];
    await pump(tester, c: controller, typing: typing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(typing, isEmpty);
    controller.dispose();
  });
}
