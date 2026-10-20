import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show AlertDialog, Text, showDialog;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_shell.dart';

import '../../support/scriptable_gateway.dart';
import 'shell_harness.dart';

void main() {
  testWidgets('system Back returns from a mobile DM to the chat list',
      (tester) async {
    final gateway = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'alice', peer: 'Alice')]);
    await pumpShellApp(tester,
        gateway: gateway, physical: const Size(400, 800));
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byType(DmScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(DmScreen), findsNothing);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byType(DmScreen), findsOneWidget);
  });

  testWidgets('system Back returns from new chat to the mobile chat list',
      (tester) async {
    await pumpShellApp(tester,
        gateway: ScriptableGateway(), physical: const Size(400, 800));
    appRouter.go(AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(ChatPaneWelcome), findsNothing);
  });

  testWidgets('system Back on the mobile chat list can leave the app',
      (tester) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => platformCalls.add(call));
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpShellApp(tester,
        gateway: ScriptableGateway(), physical: const Size(400, 800));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(platformCalls.where((c) => c.method == 'SystemNavigator.pop'),
        hasLength(1));
  });

  testWidgets('system Back dismisses a dialog before leaving the mobile DM',
      (tester) async {
    final gateway = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'alice', peer: 'Alice')]);
    await pumpShellApp(tester,
        gateway: gateway, physical: const Size(400, 800));
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.byType(DmScreen)),
      builder: (_) => const AlertDialog(content: Text('Dialog')),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(DmScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SessionsScreen), findsOneWidget);
  });
}
