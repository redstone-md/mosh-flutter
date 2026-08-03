// ConversationComposer `disabled` vs `sending` parity test (React
// ChatComposer.tsx L58/L113 distinguishes a hard `disabled` gate from an
// in-flight `sending` flag; Flutter previously conflated both into
// `sending`). The send button is the cleanest assertion target: its
// `onPressed` is null iff the gate (`sending || disabled`) is set OR the
// text is empty. Pumping the composer directly (no screen) keeps the test
// hermetic; the AttachmentPicker file dialog only opens on tap, so
// pumping it is safe.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/conversation_composer.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show PickedAttachment;
import 'package:mosh/src/features/shared/voice_composer.dart' show VoiceSend;

void main() {
  void noAttach(PickedAttachment _) {}

  void noVoice(VoiceSend _) {}

  Future<void> pump(WidgetTester tester,
      {required bool sending, required bool disabled, required TextEditingController c}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationComposer(
          controller: c,
          sending: sending,
          disabled: disabled,
          placeholder: 'p',
          sendLabel: 'Send',
          onSend: () {},
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

  testWidgets('disabled gate (independent of sending) disables the send button',
      (tester) async {
    final c = TextEditingController(text: 'hello');
    await pump(tester, sending: false, disabled: true, c: c);
    final button = find.byType(FilledButton);
    expect(button, findsOneWidget);
    final FilledButton b = tester.widget(button);
    expect(b.onPressed, isNull,
        reason: 'disabled must gate send even when not sending');
  });

  testWidgets('disabled false + sending false + non-empty text enables send',
      (tester) async {
    final c = TextEditingController(text: 'hello');
    await pump(tester, sending: false, disabled: false, c: c);
    final FilledButton b = tester.widget(find.byType(FilledButton));
    expect(b.onPressed, isNotNull,
        reason: 'send enabled when not sending, not disabled, non-empty');
  });

  testWidgets('sending true disables send even when disabled false',
      (tester) async {
    final c = TextEditingController(text: 'hello');
    await pump(tester, sending: true, disabled: false, c: c);
    final FilledButton b = tester.widget(find.byType(FilledButton));
    expect(b.onPressed, isNull,
        reason: 'sending gates send even when disabled is false');
  });
}
