import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/message_copy.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_builders.dart';
import '../../support/message_selection.dart';
import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

DmConversation _snapshot(String target, List<String> ids) => DmConversation(
    DmTarget(target),
    TestSnapshots.dm(sessionId: target, messages: [
      for (final id in ids)
        TestMessage(body: 'same text', messageId: id).toDm(),
    ]));

Future<void> _pumpList(WidgetTester tester,
        ValueNotifier<DmConversation> snapshot, ScriptableGateway gateway) =>
    pumpScreen(
        tester,
        Scaffold(
          body: ValueListenableBuilder(
            valueListenable: snapshot,
            builder: (context, current, child) => ConversationMessageListView(
              messages: current.messages,
              snapshot: current,
              attachmentCallbacks: (view, {required bool own}) =>
                  ConversationAttachmentCallbacks(
                busy: false,
                onDownload: (_) {},
                onCancel: (_) {},
                onOpen: (_) {},
              ),
              onRetryMessage: (_) {},
            ),
          ),
        ),
        overrides: [gatewayProvider.overrideWithValue(gateway)]);

Future<void> _pumpText(WidgetTester tester) => pumpScreen(
    tester,
    const Scaffold(
      body: MessageSelectionArea(
        child: CopyableMessage(
          body: 'first word',
          child:
              Padding(padding: EdgeInsets.all(24), child: Text('first word')),
        ),
      ),
    ));

Future<void> _pumpSelectable(WidgetTester tester, VoidCallback onSelect,
        {EdgeInsets viewInsets = EdgeInsets.zero}) =>
    pumpScreen(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: MessageSelectionArea(
                child: CopyableMessage(
                  body: 'first word',
                  onSelect: onSelect,
                  child: const Padding(
                      padding: EdgeInsets.all(24), child: Text('first word')),
                ),
              ),
            ),
          ),
        ));

void _performCustomAction(WidgetTester tester, Finder finder, String label) {
  final id =
      CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label));
  SemanticsNode? node = tester.getSemantics(finder);
  while (!(node!.getSemanticsData().customSemanticsActionIds?.contains(id) ??
      false)) {
    node = node.parent;
  }
  node.owner!.performAction(node.id, SemanticsAction.customAction, id);
}

double _menuScale(WidgetTester tester) {
  final menu = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('message-context-menu')));
  return (menu.localToGlobal(const Offset(100, 0)) -
              menu.localToGlobal(Offset.zero))
          .distance /
      100;
}

void main() {
  testWidgets('screen readers can long-press an attachment to open its menu',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpConversation(tester, conversationCases().first, messages: [
        TestMessage(
            messageId: 'file',
            attachment: testAttachment(attachmentId: 'file')),
      ]);
      tester.semantics.longPress(find.semantics.byLabel(RegExp('report.pdf')));
      await tester.pumpAndSettle();
      expect(find.text('Select message'), findsOneWidget);
      expect(find.text('Delete…'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('equal-body insertion dismisses the old deletion target',
      (tester) async {
    final snapshot = ValueNotifier(_snapshot('chat', ['original']));
    addTearDown(snapshot.dispose);
    final gateway = ScriptableGateway();
    await _pumpList(tester, snapshot, gateway);
    await clickMessage(tester, tester.getCenter(find.text('same text')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete…'), findsOneWidget);
    snapshot.value = _snapshot('chat', ['original', 'new']);
    await tester.pumpAndSettle();
    expect(find.text('Delete…'), findsNothing);
    await clickMessage(tester,
        tester.getCenter(find.byKey(const ValueKey('message-bubble-original'))),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    expect(gateway.lastCall(GatewayMethod.deleteMessages)!.args['messageIds'],
        ['original']);
  });

  testWidgets('switching chats dismisses an equal-body equal-id menu',
      (tester) async {
    final snapshot = ValueNotifier(_snapshot('first', ['same-id']));
    addTearDown(snapshot.dispose);
    final gateway = ScriptableGateway();
    await _pumpList(tester, snapshot, gateway);
    await clickMessage(tester, tester.getCenter(find.text('same text')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete…'), findsOneWidget);
    snapshot.value = _snapshot('second', ['same-id']);
    await tester.pumpAndSettle();
    expect(find.text('Delete…'), findsNothing);
    expect(gateway.lastCall(GatewayMethod.deleteMessages), isNull);
  });

  testWidgets('copy shortcut works while the menu owns focus', (tester) async {
    final copied = captureClipboard(tester);
    await _pumpText(tester);
    final point =
        tester.getTopLeft(find.text('first word')) + const Offset(8, 8);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    await clickMessage(tester, point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, ['first']);
    expect(find.text('Copy selected text'), findsOneWidget);
    await tester.tap(find.text('Copy selected text'));
    await tester.pumpAndSettle();
    expect(copied, ['first', 'first']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('every fresh opening starts at scale 0.97', (tester) async {
    await _pumpText(tester);
    final point = tester.getCenter(find.text('first word'));
    for (var opening = 0; opening < 2; opening++) {
      await tester.tapAt(point,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(_menuScale(tester), closeTo(0.97, 0.0001));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('screen-reader select action clears the text selection',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var selected = 0;
      await _pumpSelectable(tester, () => selected++);
      final point =
          tester.getTopLeft(find.text('first word')) + const Offset(8, 8);
      await clickMessage(tester, point);
      await clickMessage(tester, point);
      _performCustomAction(tester, find.text('first word'), 'Select message');
      await tester.pumpAndSettle();
      expect(selected, 1);
      Focus.of(tester.element(find.text('first word'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.text('Copy message'), findsOneWidget);
      expect(find.text('Copy selected text'), findsNothing);
    } finally {
      semantics.dispose();
    }
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('insets larger than the viewport still paint the menu',
      (tester) async {
    tester.view.viewInsets =
        FakeViewPadding(bottom: 700 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await _pumpSelectable(tester, () {},
        viewInsets: const EdgeInsets.only(bottom: 700));
    await clickMessage(tester, tester.getCenter(find.text('first word')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('message-context-menu')), findsOneWidget);
  });
}
