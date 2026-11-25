// The far end of the ConversationComposer: the microphone while there is
// nothing to send, Send once there is. The composer keeps a hard `disabled`
// gate distinct from the in-flight `sending` flag: sending permits more
// text. Pumping the composer directly (no screen) keeps the test hermetic;
// the AttachmentPicker file dialog only opens on tap, so pumping it is safe.
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show PickedAttachment;
import 'package:mosh/src/features/shared/voice_composer.dart' show VoiceSend;

import '../../support/voice_recorder.dart';

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
      theme: moshThemeData,
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
          voiceLabels: testVoiceLabels,
          inputDeviceId: () => null,
          onSendVoice: noVoice,
          onVoiceError: (_) {},
        ),
      ),
    ));
  }

  IconButton send(WidgetTester tester) => tester.widget(find.descendant(
      of: find.byKey(kComposerSendButtonKey),
      matching: find.byType(IconButton)));

  IconButton microphone(WidgetTester tester) => tester.widget(find.ancestor(
      of: find.byIcon(MoshIcons.mic), matching: find.byType(IconButton)));

  testWidgets('an empty field ends in the microphone, a draft in Send',
      (tester) async {
    final c = TextEditingController();
    await pump(tester, sending: false, disabled: false, c: c);
    expect(microphone(tester).onPressed, isNotNull);
    expect(find.byKey(kComposerSendButtonKey), findsNothing);

    c.text = 'hello';
    await tester.pump();
    expect(send(tester).onPressed, isNotNull);
    expect(find.byIcon(MoshIcons.mic), findsNothing);
  });

  testWidgets('a voice recording takes over the whole field', (tester) async {
    VoiceRecorderProbe(tester);
    final c = TextEditingController();
    await pump(tester, sending: false, disabled: false, c: c);

    await tester.tap(find.byTooltip('Record'));
    await pumpVoiceFrames(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('a'), findsNothing, reason: 'no attach button');
    expect(find.text('0:00'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('disabled gate (independent of sending) takes no send',
      (tester) async {
    var sent = 0;
    final c = TextEditingController(text: 'hello');
    await pump(tester,
        sending: false, disabled: true, c: c, onSend: () => sent++);

    expect(find.byKey(kComposerSendButtonKey), findsNothing);
    expect(microphone(tester).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(sent, 0);
  });

  testWidgets('sending permits another draft and submission', (tester) async {
    final c = TextEditingController(text: 'hello');
    await pump(tester, sending: true, disabled: false, c: c);
    expect(send(tester).onPressed, isNotNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('a send on its way with an empty draft spins where Send is',
      (tester) async {
    final c = TextEditingController();
    await pump(tester, sending: true, disabled: false, c: c);
    expect(send(tester).onPressed, isNull);
    expect(find.byType(MoshSpinner), findsOneWidget);
    expect(find.byIcon(MoshIcons.mic), findsNothing);
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
    expect(tester.widget<Text>(find.text('-2')).style!.color,
        MoshColors.dark.error);
    expect(send(tester).onPressed, isNull);
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(sent, 0);

    // The send trims the draft, so trailing whitespace does not count.
    c.text = '${'x' * 10}\n  ';
    await tester.pump();
    expect(send(tester).onPressed, isNotNull);
  });
}
