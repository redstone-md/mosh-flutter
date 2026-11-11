import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/features/voice_call/voice_call_host.dart';
import 'package:mosh/src/platform/desktop_window_controller.dart';
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

/// A Linux desktop: the call shows in the main window through textures.
Future<_Window> _pump(WidgetTester tester, SessionSnapshot session) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      CallVideoTextures.channel,
      (_) async => {
            'local': [7, 4096],
            'remote': [8, 8192],
          });
  final gateway = ScriptableGateway()..seedSessions([session]);
  final bridge = ScriptableBridge(conversations: gateway.conversations);
  final owner =
      NativeCallOwner(bridge, () async => true, textures: CallVideoTextures());
  final window = _Window();
  addTearDown(window.dispose);
  final router = GoRouter(routes: [
    GoRoute(
        path: '/',
        builder: (_, __) => const VoiceCallHost(
            child: Scaffold(body: Center(child: TextField()))))
  ]);
  addTearDown(router.dispose);
  await pumpScreen(tester,
      ReleasesCallMedia(media: owner, child: Router.withConfig(config: router)),
      overrides: <Override>[
        gatewayProvider.overrideWithValue(gateway),
        bridgeFacadeProvider.overrideWithValue(bridge),
        nativeCallOwnerProvider.overrideWithValue(owner),
        desktopWindowControllerProvider.overrideWithValue(window),
      ],
      settle: false);
  await tester.pump(const Duration(milliseconds: 100));
  return window;
}

void main() {
  testWidgets(
      'a call the user started takes the window, goes full screen and '
      'leaves it when minimized', (tester) async {
    final window = await _pump(
        tester,
        TestSnapshots.dm(
            sessionId: 'origin',
            outgoingCall: const OutgoingCall(callId: 'call')));
    expect(find.byType(TextField).hitTestable(), findsNothing,
        reason: 'the expanded call covers the chats');

    await tester.tap(find.byTooltip('Enter Full Screen'));
    await tester.pump();
    expect(window.fullScreen, isTrue);
    expect(find.byTooltip('Exit Full Screen'), findsOneWidget);

    await tester.tap(find.byTooltip('Minimize call'));
    await tester.pump();
    expect(window.fullScreen, isFalse);
    expect(find.byTooltip('Cancel call'), findsOneWidget,
        reason: 'the mini view keeps the call controls');
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an incoming call rings in the mini view and expands on request',
      (tester) async {
    await _pump(
        tester,
        TestSnapshots.dm(
            sessionId: 'origin',
            pendingCall: const PendingCall(
                callId: 'call', fromDevice: 'Alice', answerPending: false)));
    expect(find.byTooltip('Accept call'), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget,
        reason: 'ringing must not take the window from the user');
    expect(find.byTooltip('Enter Full Screen'), findsNothing);

    await tester.tap(find.byTooltip('Expand call'));
    await tester.pump();
    expect(find.byTooltip('Enter Full Screen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
