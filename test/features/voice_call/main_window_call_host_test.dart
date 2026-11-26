import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';

import '../../support/message_builders.dart';
import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

/// The main window, without its platform channel.
class _Window extends DesktopWindowController {
  _Window() : super(platform: TargetPlatform.linux);

  @override
  Future<void> setFullScreen(bool fullScreen) async =>
      fullScreen ? onWindowEnterFullScreen() : onWindowLeaveFullScreen();
}

/// A Linux desktop: the call shows in the main window through textures,
/// under the title bar, with a text field standing in for the chats.
Future<({_Window window, ScriptableBridge bridge})> _pump(
    WidgetTester tester, SessionSnapshot session) async {
  mockCallVideoPlugin(tester);
  final gateway = ScriptableGateway()..seedSessions([session]);
  final bridge = ScriptableBridge(conversations: gateway.conversations);
  final owner = NativeCallOwner(bridge, () async => true);
  final window = _Window();
  addTearDown(window.dispose);
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => const VoiceCallHost(
            child: Scaffold(body: Center(child: TextField()))))
  ]);
  addTearDown(router.dispose);
  await pumpScreen(
      tester,
      ReleasesCallMedia(
          media: owner,
          child: Column(children: [
            const MoshTitleBar(onOpenPeerStatus: null),
            Expanded(child: Router.withConfig(config: router)),
          ])),
      overrides: <Override>[
        gatewayProvider.overrideWithValue(gateway),
        bridgeFacadeProvider.overrideWithValue(bridge),
        nativeCallOwnerProvider.overrideWithValue(owner),
        desktopWindowControllerProvider.overrideWithValue(window),
      ],
      settle: false);
  await tester.pump(const Duration(milliseconds: 100));
  return (window: window, bridge: bridge);
}

final _outgoing = TestSnapshots.dm(
    sessionId: 'origin',
    peerDisplayName: 'Alice',
    outgoingCall: const OutgoingCall(callId: 'call'));
final _ringing = TestSnapshots.dm(
    sessionId: 'origin',
    pendingCall: const PendingCall(
        callId: 'call', fromDevice: 'Alice', answerPending: false));

Finder _inTitleBar(Finder finder) =>
    find.descendant(of: find.byType(MoshTitleBar), matching: finder);
final _chats = find.byType(TextField).hitTestable();

void main() {
  testWidgets(
      'a call the user started takes the window, goes full screen and '
      'leaves it for the title bar when minimized', (tester) async {
    final (:window, bridge: _) = await _pump(tester, _outgoing);
    expect(_chats, findsNothing, reason: 'the open call covers the chats');
    expect(_inTitleBar(find.text('Alice')), findsNothing);

    await tester.tap(find.byTooltip('Enter Full Screen'));
    await tester.pump();
    expect(window.fullScreen, isTrue);

    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();
    expect(window.fullScreen, isFalse);
    expect(_chats, findsOneWidget);
    expect(_inTitleBar(find.text('Alice')), findsOneWidget);
    expect(_inTitleBar(find.text('Calling...')), findsOneWidget);
    expect(_inTitleBar(find.byTooltip('Cancel call')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a press on the name in the title bar opens the call again',
      (tester) async {
    await _pump(tester, _outgoing);
    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();

    await tester.tap(_inTitleBar(find.text('Alice')));
    await tester.pump();

    expect(_chats, findsNothing);
    expect(find.byTooltip('Minimize call'), findsOneWidget);
    expect(_inTitleBar(find.text('Alice')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the red button in the title bar ends the call and opens nothing',
      (tester) async {
    final (window: _, :bridge) = await _pump(tester, _outgoing);
    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();

    await tester.tap(_inTitleBar(find.byTooltip('Cancel call')));
    await tester.pump();

    expect(
        bridge.lastCall(BridgeMethod.callEnd)!.arg<String>('callId'), 'call');
    expect(_chats, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Escape minimizes the open call and keeps it running',
      (tester) async {
    await _pump(tester, _outgoing);
    expect(_chats, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_chats, findsOneWidget);
    expect(find.byTooltip('Cancel call'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'an incoming call rings in a card that leaves the chats usable and '
      'opens on a press on the person', (tester) async {
    await _pump(tester, _ringing);
    expect(find.text('Incoming voice call...'), findsOneWidget);
    expect(_chats, findsOneWidget,
        reason: 'ringing must not take the window from the user');
    expect(_inTitleBar(find.text('Alice')), findsNothing,
        reason: 'the card, not the title bar, shows a ringing call');

    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(find.byTooltip('Enter Full Screen'), findsOneWidget);
    expect(find.byTooltip('Accept call'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Accept on the card answers the call without opening it',
      (tester) async {
    final (window: _, :bridge) = await _pump(tester, _ringing);

    await tester.tap(find.text('Accept'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(bridge.lastCall(BridgeMethod.callAccept)!.arg<String>('callId'),
        'call');
    expect(_chats, findsOneWidget);
    expect(find.byTooltip('Enter Full Screen'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Decline on the card declines the call', (tester) async {
    final (window: _, :bridge) = await _pump(tester, _ringing);

    await tester.tap(find.text('Decline'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(bridge.lastCall(BridgeMethod.callDecline)!.arg<String>('callId'),
        'call');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
