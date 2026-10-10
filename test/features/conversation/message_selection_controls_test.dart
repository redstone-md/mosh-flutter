import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_selection.dart';
import '../../support/scriptable_gateway.dart';

void _expectDisabledControls(WidgetTester tester) {
  for (final label in ['Copy', 'Delete', 'Cancel']) {
    final button = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
  }
  expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
}

void main() {
  testWidgets(
      'circular selectors report checked state and support the keyboard',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpConversation(tester, conversationCases().first, messages: [
        const TestMessage.own(body: 'own note', messageId: 'm1'),
        const TestMessage(body: 'peer note', messageId: 'm2'),
        const TestMessage(body: 'legacy note'),
      ]);
      await startMessageSelection(tester, 'peer note');
      final own = find.byKey(const ValueKey('message-selector-m1'));
      final peer = find.byKey(const ValueKey('message-selector-m2'));
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(tester.getRect(own).left,
          greaterThan(tester.getRect(find.text('own note')).right));
      expect(
          tester.getSemantics(own),
          isSemantics(
              hasCheckedState: true, isChecked: false, hasTapAction: true));
      expect(tester.getSemantics(peer),
          isSemantics(hasCheckedState: true, isChecked: true));
      for (var i = 0;
          i < 12 &&
              tester
                      .getSemantics(own)
                      .getSemanticsData()
                      .flagsCollection
                      .isFocused !=
                  Tristate.isTrue;
          i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(tester.getSemantics(own), isSemantics(isFocused: true));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Selected: 2'), findsOneWidget);
      expect(tester.getSemantics(own), isSemantics(isChecked: true));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('an attachment-only selection disables Copy', (tester) async {
    await pumpConversation(tester, conversationCases().first, messages: [
      TestMessage(
          messageId: 'file', attachment: testAttachment(attachmentId: 'file')),
    ]);
    await startMessageSelection(tester, 'report.pdf');
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Copy'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'mobile deletion keeps permissions and disables actions while pending',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deletion = Completer<DeleteMessagesResult>();
    final gateway = ScriptableGateway()
      ..respondNext(GatewayMethod.deleteMessages, deletion.future);
    final copied = captureClipboard(tester);
    await pumpConversation(tester, conversationCases().first,
        gateway: gateway,
        messages: [const TestMessage(body: 'keep this', messageId: 'm1')]);
    await startMessageSelection(tester, 'keep this');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Delete for everyone'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    _expectDisabledControls(tester);
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, isEmpty);
    deletion.completeError(Exception('refused'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: 1'), findsOneWidget);
    expect(find.textContaining('Could not delete messages'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Copy'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Russian selection actions fit a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpConversation(tester, conversationCases().first, messages: [
      const TestMessage(body: 'текст', messageId: 'm1'),
    ]);
    await tester.tap(find.text('текст'),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выделить сообщение'));
    await tester.pumpAndSettle();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: 1'), findsOneWidget);
    expect(find.text('Скопировать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
  });
}
