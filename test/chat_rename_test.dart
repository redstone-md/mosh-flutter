import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/rename_chat_dialog.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'support/pump.dart';
import 'support/scriptable_gateway.dart';

void main() {
  testWidgets(
      'rejects empty names, trims accepted name and retains failed input',
      (tester) async {
    final gateway = ScriptableGateway();
    await _mount(
        tester,
        const RenameChatDialog(
            target: DmTarget('session'),
            initialName: 'Alice',
            originalName: 'Alice'),
        gateway);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(gateway.countOf(GatewayMethod.rename), 0);
    gateway.failNext(GatewayMethod.rename,
        error: StateError('storage unavailable'));
    await tester.enterText(find.byType(TextField), '  Family  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gateway.lastCall(GatewayMethod.rename)!.args['name'], 'Family');
    expect(find.text('storage unavailable'), findsOneWidget);
    expect(find.text('  Family  '), findsOneWidget);
  });

  testWidgets('reset is explicit and unavailable for shared groups',
      (tester) async {
    final gateway = ScriptableGateway();
    await _mount(
        tester,
        const RenameChatDialog(
            target: ChannelTarget('news'),
            initialName: 'Morning',
            originalName: '#news',
            hasPersonalName: true),
        gateway);
    expect(find.text('Original name: #news'), findsOneWidget);
    await tester.tap(find.text('Reset name'));
    await tester.pumpAndSettle();
    expect(gateway.countOf(GatewayMethod.resetName), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(
        tester,
        const RenameChatDialog(
            target: GroupTarget('group'),
            initialName: 'Work',
            originalName: 'Work'),
        gateway);
    expect(find.text('Reset name'), findsNothing);
  });
}

Future<void> _mount(WidgetTester tester, RenameChatDialog dialog,
    ScriptableGateway gateway) async {
  await pumpScreen(
      tester,
      Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => showDialog<void>(
                      context: context, builder: (_) => dialog),
                  child: const Text('Open')))),
      overrides: [gatewayProvider.overrideWithValue(gateway)]);
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
