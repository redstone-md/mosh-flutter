// ConversationComposer `disabled` vs `sending` test: the composer keeps a
// hard `disabled` gate distinct from the in-flight `sending` flag. The
// send button is the cleanest assertion target: its `onPressed` is null
// iff the hard gate is set or the text is empty. Sending permits more text.
// Pumping the composer directly (no screen) keeps the test hermetic; the
// AttachmentPicker file dialog only opens on tap, so pumping it is safe.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show PickedAttachment;
import 'package:mosh/src/features/shared/voice_composer.dart' show VoiceSend;

void main() {
  void noAttach(PickedAttachment _) {}

  void noVoice(VoiceSend _) {}

  Future<void> pump(WidgetTester tester,
      {required bool sending,
      required bool disabled,
      required TextEditingController c,
      int maxTextChars = 4096,
      VoidCallback? onSend}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationComposer(
          controller: c,
          sending: sending,
          disabled: disabled,
          placeholder: 'p',
          sendLabel: 'Send',
          onSend: onSend ?? () {},
          textLimit: ComposerTextLimit(
              maxChars: maxTextChars, label: (remaining) => '$remaining left'),
          attachLabel: 'a',
          onAttach: noAttach,
          onAttachmentPickError: (_) {},
          voiceRecordLabel: 'r',
          voiceDiscardLabel: 'd',
          voiceStopLabel: 's',
          voicePlayLabel: 'pl',
          voiceSendLabel: 'vs',
          voicePermissionDeniedLabel: 'denied',
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

  testWidgets('sending permits another draft and submission', (tester) async {
    final c = TextEditingController(text: 'hello');
    await pump(tester, sending: true, disabled: false, c: c);
    final FilledButton b = tester.widget(find.byType(FilledButton));
    expect(b.onPressed, isNotNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('the counter appears near the limit and counts characters',
      (tester) async {
    final c = TextEditingController(text: 'hi');
    await pump(tester,
        sending: false, disabled: false, c: c, maxTextChars: 300);
    expect(find.text('298'), findsNothing);

    c.text = '😀' * 150;
    await tester.pump();
    expect(find.text('150'), findsOneWidget);
    expect(find.bySemanticsLabel('150 left'), findsOneWidget);
  });

  testWidgets('a text over the limit cannot be sent', (tester) async {
    var sent = 0;
    final c = TextEditingController(text: 'x' * 12);
    await pump(tester,
        sending: false,
        disabled: false,
        c: c,
        maxTextChars: 10,
        onSend: () => sent++);
    expect(find.text('-2'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(sent, 0);

    // The send trims the draft, so trailing whitespace does not count.
    c.text = '${'x' * 10}\n  ';
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
