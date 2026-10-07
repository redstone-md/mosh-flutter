import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/pump.dart';
import '../../support/message_builders.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/settings.dart';

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<GoRouter> _route(WidgetTester tester,
        [String location = AppRoutes.settings]) =>
    pumpRoute(tester, location, overrides: [
      ...settingsAudioOverrides(),
      gatewayProvider.overrideWithValue(ScriptableGateway()),
    ]);

void main() {
  testWidgets('gear opens standalone settings and returns to preserved chats',
      (tester) async {
    _size(tester, const Size(1200, 850));
    final router = await _route(tester, AppRoutes.sessions);
    final railState = tester.state(find.byType(SessionsScreen));
    await tester.enterText(find.byType(TextField).first, 'retained search');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(MoshShell), findsNothing);
    expect(find.byType(SessionsScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
    await tester.tap(find.text('Back to chats'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.sessions);
    expect(tester.state(find.byType(SessionsScreen)), same(railState));
    expect(find.text('retained search'), findsOneWidget);
  });

  testWidgets('wide sidebar switches sections and remembers on reopening',
      (tester) async {
    _size(tester, const Size(1200, 850));
    final router = await _route(tester, AppRoutes.sessions);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Sound'), findsNWidgets(2));
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsNWidgets(2));
    expect(find.text('Microphone'), findsNothing);
  });

  testWidgets('closing settings restores the open chat, scroll and draft',
      (tester) async {
    _size(tester, const Size(1200, 850));
    final gateway = ScriptableGateway()
      ..seedSessions([
        TestSnapshots.dm(
            sessionId: 'alice',
            peerDisplayName: 'Alice',
            messages: [
              for (var i = 0; i < 40; i++)
                TestMessages.dm(fromDevice: 'Alice', body: 'Message $i'),
            ]),
      ]);
    final router = await pumpRoute(tester, AppRoutes.sessions, overrides: [
      ...settingsAudioOverrides(),
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
    ]);
    await tester.tap(find.descendant(
        of: find.byType(SessionsScreen), matching: find.text('Alice')));
    await tester.pumpAndSettle();
    final composer = find.descendant(
        of: find.byType(ConversationComposer),
        matching: find.byType(TextField));
    await tester.enterText(composer, 'retained draft');
    final scrollFinder = find.descendant(
        of: find.byType(ConversationMessageListView),
        matching: find.byType(Scrollable));
    final scroll = tester.state<ScrollableState>(scrollFinder);
    scroll.position.jumpTo(180);
    await tester.pump();
    final offset = scroll.position.pixels;
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationComposer), findsNothing);
    await tester.tap(find.text('Back to chats'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path,
        AppRoutes.dmFor('alice'));
    expect(find.text('retained draft'), findsOneWidget);
    expect(tester.state(scrollFinder), same(scroll));
    expect(scroll.position.pixels, offset);
  });

  testWidgets('narrow sections open as details and Back returns to the list',
      (tester) async {
    _size(tester, const Size(390, 844));
    await _route(tester);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Microphone'), findsNothing);
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Connection'), findsNothing);
    await tester.tap(find.byTooltip('Back to settings sections'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone'), findsNothing);
    expect(find.text('Connection'), findsOneWidget);
  });

  testWidgets('system Back and Escape unwind narrow detail before settings',
      (tester) async {
    _size(tester, const Size(390, 844));
    final router = await _route(tester, AppRoutes.sessions);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.sessions);
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('direct settings entry can return to the chat list',
      (tester) async {
    _size(tester, const Size(1200, 850));
    final router = await _route(tester);
    await tester.tap(find.text('Back to chats'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.sessions);
  });

  testWidgets('reopening narrow settings starts at the section list',
      (tester) async {
    _size(tester, const Size(390, 844));
    await _route(tester, AppRoutes.sessions);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Microphone'), findsNothing);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
  });

  testWidgets('the start menu keeps creation separate from settings',
      (tester) async {
    await pumpScreen(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: StartMenu(
              onPickChat: _noop,
              onPickGroup: _noop,
              onPickChannel: _noop,
              onPickJoin: _noop,
            ),
          ),
        ));
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.byIcon(Icons.verified_user), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
  });
}

void _noop() {}
